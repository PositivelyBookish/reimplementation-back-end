# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AssignmentQuestionnaire, type: :model do
  describe 'review rubric uniqueness' do
    let(:assignment) { create(:assignment) }
    let(:topic) { create(:project_topic, assignment: assignment) }
    let(:instructor) { assignment.instructor.becomes(Instructor) }
    let(:first_questionnaire) do
      Questionnaire.create!(
        name: 'Security Review Rubric',
        instructor: instructor,
        questionnaire_type: 'ReviewQuestionnaire',
        display_type: 'Review',
        min_question_score: 0,
        max_question_score: 5
      )
    end
    let(:second_questionnaire) do
      Questionnaire.create!(
        name: 'Compliance Review Rubric',
        instructor: instructor,
        questionnaire_type: 'ReviewQuestionnaire',
        display_type: 'Review',
        min_question_score: 0,
        max_question_score: 5
      )
    end

    it 'allows multiple different review rubrics for the same assignment topic and round' do
      described_class.create!(
        assignment: assignment,
        questionnaire: first_questionnaire,
        project_topic: topic,
        used_in_round: 1
      )

      mapping = described_class.new(
        assignment: assignment,
        questionnaire: second_questionnaire,
        project_topic: topic,
        used_in_round: 1
      )

      expect(mapping).to be_valid
    end

    it 'rejects an exact duplicate review rubric mapping for the same assignment topic and round' do
      described_class.create!(
        assignment: assignment,
        questionnaire: first_questionnaire,
        project_topic: topic,
        used_in_round: 1
      )

      duplicate = described_class.new(
        assignment: assignment,
        questionnaire: first_questionnaire,
        project_topic: topic,
        used_in_round: 1
      )

      expect(duplicate).not_to be_valid
      expect(duplicate.errors.full_messages).to include(
        'review rubric already exists for this assignment, topic, round, and questionnaire'
      )
    end
  end
end
