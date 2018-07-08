# frozen_string_literal: true

require 'rails_helper'

describe Monarchy::Validators do
  let(:user) { create(:user) }
  let(:resource) { create(:memo) }

  describe 'in normal mode' do
    it 'query database' do
      expect { user.member_for(resource) }.to make_database_queries(count: 15)
    end
  end

  describe 'in testing mode' do
    before do
      Monarchy.passthrough = true
    end

    after do
      Monarchy.passthrough = false
    end

    it "doesn't query database for Monarchy related data" do
      expect { user.member_for(resource) }.to make_database_queries(manipulative: true, count: 2)
    end
  end
end
