# frozen_string_literal: true
require 'rails_helper'

RSpec.describe Assignment, type: :model do

  let(:team) {Team.new}
  let(:assignment) { Assignment.new(id: 1, name: 'Test Assignment') }
  let(:review_response_map) { ReviewResponseMap.new(assignment: assignment, reviewee: team) }
  let(:answer) { Answer.new(answer: 1, comments: 'Answer text', item_id: 1) }
  let(:answer2) { Answer.new(answer: 1, comments: 'Answer text', item_id: 1) }
  
  include RolesHelper
  before(:all) { @roles = create_roles_hierarchy } # Create the full roles hierarchy once for creating the instructor role later
  let(:institution) { Institution.create!(name: "NC State") } # All users belong to the same institution to satisfy foreign key constraints.
  let(:instructor) { User.create!(name: "instructor", full_name: "Instructor User", email: "instructor@example.com", password_digest: "password", role_id: @roles[:instructor].id, institution_id: institution.id) }

  describe '#num_review_rounds' do
    it 'counts review due dates to determine the number of rounds' do
      assignment = Assignment.create!(name: 'Round Count', instructor: instructor, vary_by_round: true)
      AssignmentDueDate.create!(parent: assignment, due_at: 1.day.from_now,
                                deadline_type_id: DueDate::REVIEW_DEADLINE_TYPE_ID,
                                submission_allowed_id: 3, review_allowed_id: 3)
      AssignmentDueDate.create!(parent: assignment, due_at: 2.days.from_now,
                                deadline_type_id: DueDate::REVIEW_DEADLINE_TYPE_ID,
                                submission_allowed_id: 3, review_allowed_id: 3)

      expect(assignment.num_review_rounds).to eq(2)
    end

    it 'ignores non-review deadlines when counting rounds' do
      assignment = Assignment.create!(name: 'Mixed Deadlines', instructor: instructor, vary_by_round: true)
      AssignmentDueDate.create!(parent: assignment, due_at: 1.day.from_now,
                                deadline_type_id: 99,
                                submission_allowed_id: 3, review_allowed_id: 3)
      AssignmentDueDate.create!(parent: assignment, due_at: 2.days.from_now,
                                deadline_type_id: DueDate::REVIEW_DEADLINE_TYPE_ID,
                                submission_allowed_id: 3, review_allowed_id: 3)

      expect(assignment.num_review_rounds).to eq(1)
    end
  end

  describe '#varying_rubrics_by_round?' do
    let(:questionnaire) { Questionnaire.create!(name: 'Review Q', instructor_id: instructor.id, questionnaire_type: 'ReviewQuestionnaire',
                                                display_type: 'Review', min_question_score: 0, max_question_score: 5) }

    it 'returns false when vary_by_round is disabled even if rounds exist' do
      assignment = Assignment.create!(name: 'No Vary', instructor: instructor, vary_by_round: false)
      AssignmentQuestionnaire.create!(assignment: assignment, questionnaire: questionnaire, used_in_round: 1)

      expect(assignment.varying_rubrics_by_round?).to be false
    end

    it 'returns true when vary_by_round is enabled and a round-specific rubric exists' do
      assignment = Assignment.create!(name: 'Vary', instructor: instructor, vary_by_round: true)
      AssignmentQuestionnaire.create!(assignment: assignment, questionnaire: questionnaire, used_in_round: 1)

      expect(assignment.varying_rubrics_by_round?).to be true
    end
  end

  describe '#assignment_questionnaires_for_response_map' do
    let(:assignment) { create(:assignment, vary_by_topic: true) }
    let(:topic) { create(:project_topic, assignment: assignment) }
    let(:reviewee_team) { AssignmentTeam.create!(name: 'Database Team', parent_id: assignment.id, type: 'AssignmentTeam') }
    let(:review_response_map) { ReviewResponseMap.new(assignment: assignment, reviewee: reviewee_team) }
    let(:instructor) { assignment.instructor.becomes(Instructor) }
    let(:topic_questionnaire_one) do
      Questionnaire.create!(
        name: 'Topic Review Rubric 1',
        instructor: instructor,
        questionnaire_type: 'ReviewQuestionnaire',
        display_type: 'Review',
        min_question_score: 0,
        max_question_score: 5
      )
    end
    let(:topic_questionnaire_two) do
      Questionnaire.create!(
        name: 'Topic Review Rubric 2',
        instructor: instructor,
        questionnaire_type: 'ReviewQuestionnaire',
        display_type: 'Review',
        min_question_score: 0,
        max_question_score: 5
      )
    end
    let(:default_questionnaire) do
      Questionnaire.create!(
        name: 'Default Review Rubric',
        instructor: instructor,
        questionnaire_type: 'ReviewQuestionnaire',
        display_type: 'Review',
        min_question_score: 0,
        max_question_score: 5
      )
    end

    before do
      SignedUpTeam.create!(project_topic: topic, team: reviewee_team, is_waitlisted: false)
    end

    it 'returns all topic and round specific review rubrics in a stable order' do
      first_mapping = AssignmentQuestionnaire.create!(
        assignment: assignment,
        questionnaire: topic_questionnaire_one,
        project_topic: topic,
        used_in_round: 1
      )
      second_mapping = AssignmentQuestionnaire.create!(
        assignment: assignment,
        questionnaire: topic_questionnaire_two,
        project_topic: topic,
        used_in_round: 1
      )
      AssignmentQuestionnaire.create!(
        assignment: assignment,
        questionnaire: default_questionnaire,
        used_in_round: 1
      )

      expect(
        assignment.assignment_questionnaires_for_response_map(review_response_map, round: 1)
      ).to eq([first_mapping, second_mapping])
    end

    it 'falls back to assignment defaults when no topic-specific rubric exists for the round' do
      default_mapping = AssignmentQuestionnaire.create!(
        assignment: assignment,
        questionnaire: default_questionnaire,
        used_in_round: 1
      )

      expect(
        assignment.assignment_questionnaires_for_response_map(review_response_map, round: 1)
      ).to eq([default_mapping])
    end
  end

  describe '.get_all_review_comments' do
    it 'returns concatenated review comments and # of reviews in each round' do
      allow(Assignment).to receive(:find).with(1).and_return(assignment)
      allow(assignment).to receive(:num_review_rounds).and_return(2)
      allow(ReviewResponseMap).to receive_message_chain(:where, :find_each).with(reviewed_object_id: 1, reviewer_id: 1)
                                                                           .with(no_args).and_yield(review_response_map)
      response1 = double('Response', round: 1, additional_comment: '')
      response2 = double('Response', round: 2, additional_comment: 'LGTM')
      allow(review_response_map).to receive(:responses).and_return([response1, response2])
      allow(response1).to receive(:scores).and_return([answer])
      allow(response2).to receive(:scores).and_return([answer2])
      expect(assignment.get_all_review_comments(1)).to eq([[nil, 'Answer text', 'Answer textLGTM', ''], [nil, 1, 1, 0]])
    end
  end

  # Get a collection of all comments across all rounds of a review as well as a count of the total number of comments. Returns the above
  # information both for totals and in a list per-round.
  describe '.volume_of_review_comments' do
    it 'returns volumes of review comments in each round' do
      allow(assignment).to receive(:get_all_review_comments).with(1)
                                                                  .and_return([[nil, 'Answer text', 'Answer textLGTM', ''], [nil, 1, 1, 0]])
      expect(assignment.volume_of_review_comments(1)).to eq([1, 2, 2, 0])
    end
  end
end
