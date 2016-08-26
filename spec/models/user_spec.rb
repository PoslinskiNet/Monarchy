# frozen_string_literal: true
require 'rails_helper'

describe User, type: :model do
  it { is_expected.to have_many(:members).dependent(:destroy) }
  it { is_expected.to have_many(:hierarchies).through(:members) }

  let!(:guest_role) { create(:role, name: :guest, level: 0, inherited: false) }
  let!(:member_role) { create(:role, name: :member, level: 1) }
  let!(:manager_role) { create(:role, name: :manager, level: 2) }

  let(:user) { create :user }
  let!(:project) { create :project }
  let!(:memo) { create :memo, parent: project }

  describe '#roles_for' do
    let!(:memo_member) { create(:member, user: user, hierarchy: memo.hierarchy, roles: [member_role]) }
    let!(:project_member) { create(:member, user: user, hierarchy: project.hierarchy, roles: [manager_role]) }

    let(:project_roles) { user.roles_for(project) }
    subject { user.roles_for(memo) }

    context 'inherited_role from higher level' do
      let!(:owner_role) { create(:role, name: :owner, level: 3) }
      let!(:manager_role) { create(:role, name: :manager, level: 2, inherited_role: owner_role) }

      it { is_expected.to match_array([owner_role, member_role]) }

      context 'do not map self roles' do
        let!(:memo_member) { create(:member, user: user, hierarchy: memo.hierarchy, roles: [manager_role]) }
        let!(:project_member) { create(:member, user: user, hierarchy: project.hierarchy, roles: [member_role]) }

        it { is_expected.to match_array([manager_role, member_role]) }
      end
    end

    context 'roles without inheritece' do
      let(:project_roles) { user.roles_for(project, false) }
      subject { user.roles_for(memo, false) }

      it { expect(project_roles).to match_array([manager_role]) }
      it { is_expected.to match_array([member_role]) }

      context 'where memo has no roles' do
        let!(:memo_member) {}

        it { expect(project_roles).to match_array([manager_role]) }
        it { is_expected.to eq([]) }
      end
    end

    context 'user has no direct access to memo' do
      let!(:memo_member) {}

      it { expect(project_roles).to match_array([manager_role]) }
      it { is_expected.to match_array([manager_role]) }
    end

    context 'user has no direct access to project' do
      let!(:project_member) {}

      it { expect(project_roles).to match_array([guest_role]) }
      it { is_expected.to match_array([member_role]) }
    end

    context 'returns all roles with the higher level' do
      let(:member_role) { create(:role, name: :member, level: 2) }

      it { expect(project_roles).to match_array([manager_role]) }
      it { is_expected.to match_array([manager_role, member_role]) }

      context 'returns non duplicated roles' do
        let!(:project_member) do
          create(:member, user: user,
                          hierarchy: project.hierarchy,
                          roles: [manager_role, member_role])
        end

        it { expect(project_roles).to match_array([manager_role, member_role]) }
        it { is_expected.to match_array([manager_role, member_role]) }
      end
    end

    context 'parent role is not inherited' do
      let(:manager_role) { create(:role, name: :manager, level: 2, inherited: false) }

      it { expect(project_roles).to match_array([manager_role]) }
      it { is_expected.to match_array([member_role]) }
    end

    context 'when model is not acting_as_resource' do
      subject { user.roles_for(user) }
      it { expect { subject }.to raise_exception(Monarchy::Exceptions::ModelNotResource) }
    end

    context 'when model is nil' do
      subject { user.roles_for(nil) }
      it { expect { subject }.to raise_exception(Monarchy::Exceptions::ResourceIsNil) }
    end

    context 'when model is not model' do
      subject { user.roles_for('oko') }
      it { expect { subject }.to raise_exception(Monarchy::Exceptions::ModelNotResource) }
    end
  end

  describe '#grant' do
    shared_examples 'granted with correct members' do
      it { expect(Monarchy::Member.count).to be(1) }
      it { expect(parent.members).to be_empty }
      it { expect(resource.members.count).to be(1) }
      it { expect(resource.members.first.roles).to match_array([manager_role]) }
    end

    context 'role does not exist' do
      subject { user.grant(:phantom, memo) }

      it { expect { subject }.to raise_exception(Monarchy::Exceptions::RoleNotExist) }
    end

    context 'memo resource with project as parent' do
      let!(:grant_user) { user.grant(:manager, memo) }

      it_behaves_like 'granted with correct members' do
        let(:resource) { memo }
        let(:parent) { project }
      end

      it 'doubled granted' do
        2.times do
          grant_user
          expect(project.members).to be_empty
          expect(memo.members.first.roles).to match_array([manager_role])
        end
      end
    end

    context 'parent resource' do
      let!(:grant_user) { user.grant(:manager, project) }

      it_behaves_like 'granted with correct members' do
        let(:resource) { project }
        let(:parent) { memo }
      end
    end

    context 'when model is not acting_as_resource' do
      subject { user.grant(:manager, user) }
      it { expect { subject }.to raise_exception(Monarchy::Exceptions::ModelNotResource) }
    end

    context 'when model is nil' do
      subject { user.grant(:manager, nil) }
      it { expect { subject }.to raise_exception(Monarchy::Exceptions::ResourceIsNil) }
    end

    context 'when model is not model' do
      subject { user.grant(:manager, 'oko') }
      it { expect { subject }.to raise_exception(Monarchy::Exceptions::ModelNotResource) }
    end
  end

  describe '#member_for' do
    let!(:memo_member) { create(:member, user: user, hierarchy: memo.hierarchy, roles: [member_role]) }

    context 'member exist' do
      it { expect(user.member_for(memo)).to eq(memo_member) }
    end

    context 'member not exist' do
      it { expect(user.member_for(project)).to be_nil }
    end

    context 'when model is not acting_as_resource' do
      subject { user.member_for(user) }
      it { expect { subject }.to raise_exception(Monarchy::Exceptions::ModelNotResource) }
    end

    context 'when model is nil' do
      subject { user.member_for(nil) }
      it { expect { subject }.to raise_exception(Monarchy::Exceptions::ResourceIsNil) }
    end

    context 'when model is not model' do
      subject { user.member_for('oko') }
      it { expect { subject }.to raise_exception(Monarchy::Exceptions::ModelNotResource) }
    end
  end

  describe '#revoke access' do
    let!(:memo2) { create :memo, parent: memo }
    let!(:memo4) { create :memo, parent: memo }
    let!(:memo3) { create :memo, parent: memo2 }

    let(:other_user) { create :user }

    context 'sholud revoke bellow and self' do
      context 'with deafult hierarchy_ids' do
        before do
          user.grant(:manager, project)
          user.grant(:manager, memo3)
          user.grant(:member, memo4)
          other_user.grant(:manager, memo3)

          user.revoke_access(memo2)
        end

        it { expect(project.members.count).to eq(1) }
        it { expect(memo.members.count).to eq(0) }
        it { expect(memo2.members.count).to eq(0) }
        it { expect(memo3.members.count).to eq(1) }
        it { expect(memo4.members.count).to eq(1) }
      end

      context 'with custom hierarchy_ids' do
        before do
          user.grant(:member, project)
          user.grant(:member, memo)
          user.grant(:member, memo3)
          user.grant(:member, memo4)

          user.revoke_access(memo, memo.hierarchy.descendant_ids)
        end

        it { expect(project.members.count).to eq(1) }
        it { expect(memo.members.count).to eq(1) }
        it { expect(memo2.members.count).to eq(0) }
        it { expect(memo3.members.count).to eq(0) }
        it { expect(memo4.members.count).to eq(0) }
      end
    end

    context 'when model is not acting_as_resource' do
      subject { user.revoke_access(user) }
      it { expect { subject }.to raise_exception(Monarchy::Exceptions::ModelNotResource) }
    end

    context 'when model is nil' do
      subject { user.revoke_access(nil) }
      it { expect { subject }.to raise_exception(Monarchy::Exceptions::ResourceIsNil) }
    end

    context 'when model is not model' do
      subject { user.revoke_access('oko') }
      it { expect { subject }.to raise_exception(Monarchy::Exceptions::ModelNotResource) }
    end
  end

  describe '#revoke role' do
    let!(:memo2) { create :memo, parent: memo }
    let!(:memo3) { create :memo, parent: memo2 }
    let!(:memo4) { create :memo, parent: memo }

    context 'sholud revoke only one role' do
      subject { user.revoke_role(:manager, memo4) }

      before do
        user.grant(:manager, memo4)
        user.grant(:member, memo4)
      end

      it { expect { subject }.to change { Monarchy::MembersRole.count }.by(-1) }
      it { is_expected.to be 1 }

      it do
        subject
        expect(memo4.members.first.roles).to match_array([member_role])
      end
    end

    context 'when user has not member' do
      subject { user.revoke_role(:manager, memo4) }

      it { expect { subject }.not_to change { Monarchy::MembersRole.count } }
      it { expect { subject }.not_to change { Member.count } }
      it { is_expected.to be 0 }
    end

    context 'when revoke last role' do
      before do
        user.grant(:manager, memo3)
      end

      context 'which is default role' do
        before do
          user.revoke_role(:guest, memo3)
        end

        it { expect(memo3.members.first.roles).to match_array([manager_role]) }

        context 'and then revoke the manager one' do
          before do
            user.revoke_role(:manager, memo3)
          end

          it { expect(memo3.members.first.roles).to be_empty }
        end
      end

      context 'which is not default role' do
        before do
          user.revoke_role(:manager, memo3)
        end

        it { expect(memo3.members.first.roles).to be_empty }

        context 'and then revoke the default one' do
          before do
            user.revoke_role(:guest, memo3)
          end

          it { expect(memo3.members.first.roles).to be_empty }
        end
      end
    end

    context 'when model is not acting_as_resource' do
      subject { user.revoke_role(:guest, user) }
      it { expect { subject }.to raise_exception(Monarchy::Exceptions::ModelNotResource) }
    end

    context 'when model is nil' do
      subject { user.revoke_role(:guest, nil) }
      it { expect { subject }.to raise_exception(Monarchy::Exceptions::ResourceIsNil) }
    end

    context 'when model is not model' do
      subject { user.revoke_role(:guest, 'oko') }
      it { expect { subject }.to raise_exception(Monarchy::Exceptions::ModelNotResource) }
    end
  end

  describe '#revoke role!' do
    let!(:memo2) { create :memo, parent: memo }

    context 'sholud revoke only one role' do
      subject { user.revoke_role!(:manager, memo2) }

      before do
        user.grant(:manager, memo2)
        user.grant(:member, memo2)
      end

      it { expect { subject }.to change { Monarchy::MembersRole.count }.by(-1) }

      it do
        subject
        expect(memo2.members.first.roles).to match_array([member_role])
      end
    end

    context 'when revoke last role' do
      before do
        user.grant(:manager, memo2)
      end

      context 'which is default role' do
        before do
          user.revoke_role!(:guest, memo2)
        end

        it { expect(memo2.members.first.roles).to match_array([manager_role]) }

        context 'and then revoke the manager one' do
          let!(:memo3) { create :memo, parent: memo2 }

          before do
            user.grant(:manager, memo3)
            user.revoke_role!(:manager, memo2)
          end

          it { expect(memo2.members).to be_empty }
          it { expect(memo3.members).to be_empty }
        end
      end

      context 'which is not default role' do
        let!(:memo3) { create :memo, parent: memo2 }

        before do
          user.revoke_role!(:manager, memo2)
        end

        it { expect(memo2.members).to be_empty }
        it { expect(memo3.members).to be_empty }
      end
    end

    context 'when model is not acting_as_resource' do
      subject { user.revoke_role!(:guest, user) }
      it { expect { subject }.to raise_exception(Monarchy::Exceptions::ModelNotResource) }
    end

    context 'when model is nil' do
      subject { user.revoke_role!(:guest, nil) }
      it { expect { subject }.to raise_exception(Monarchy::Exceptions::ResourceIsNil) }
    end

    context 'when model is not model' do
      subject { user.revoke_role!(:guest, 'oko') }
      it { expect { subject }.to raise_exception(Monarchy::Exceptions::ModelNotResource) }
    end
  end
end
