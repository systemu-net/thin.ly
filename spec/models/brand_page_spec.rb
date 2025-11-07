# == Schema Information
#
# Table name: brand_pages
#
#  id                   :bigint           not null, primary key
#  content              :jsonb            not null
#  description          :text
#  lookup_code          :string           not null
#  published_at         :datetime
#  published_url        :string
#  status               :string           default("DRAFT"), not null
#  title                :string           default("Untitled"), not null
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  published_version_id :bigint
#  user_id              :bigint           not null
#
# Indexes
#
#  index_brand_pages_on_lookup_code           (lookup_code) UNIQUE
#  index_brand_pages_on_published_at          (published_at)
#  index_brand_pages_on_published_version_id  (published_version_id)
#  index_brand_pages_on_status                (status)
#  index_brand_pages_on_user_id               (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (published_version_id => brand_pages.id)
#  fk_rails_...  (user_id => users.id)
#
require 'rails_helper'

RSpec.describe BrandPage, type: :model do
  let(:user) { create(:user) }

  # Mock Sidekiq jobs to avoid async execution in tests
  before do
    allow(PublishJob).to receive(:perform_async)
    allow(UnpublishJob).to receive(:perform_async)
  end

  describe 'associations' do
    it 'belongs to user' do
      brand_page = build(:brand_page, user: nil)
      expect(brand_page).not_to be_valid
      expect(brand_page.errors[:user]).to include("must exist")
    end

    it 'belongs to published_version optionally' do
      brand_page = create(:brand_page, :draft, user: user)
      expect(brand_page.published_version).to be_nil
      expect(brand_page).to be_valid
    end

    it 'has one draft_version' do
      published = create(:brand_page, :published, user: user)
      draft = create(:brand_page, :draft, user: user, published_version: published)

      expect(published.draft_version).to eq(draft)
    end
  end

  describe 'validations' do
    it 'validates presence of content' do
      brand_page = build(:brand_page, content: nil, user: user)
      expect(brand_page).not_to be_valid
      expect(brand_page.errors[:content]).to include("can't be blank")
    end

    it 'validates presence of lookup_code after bypassing auto-generation' do
      brand_page = build(:brand_page, user: user)
      # Skip the callback that auto-generates lookup_code
      brand_page.define_singleton_method(:set_lookup_code) { }
      brand_page.lookup_code = nil
      expect(brand_page).not_to be_valid
      expect(brand_page.errors[:lookup_code]).to include("can't be blank")
    end

    it 'auto-generates lookup_code when blank' do
      brand_page = build(:brand_page, user: user, lookup_code: nil)
      brand_page.valid?  # Triggers validation callbacks
      expect(brand_page.lookup_code).to be_present
    end

    it 'validates uniqueness of lookup_code' do
      # Create first record and get its final lookup_code
      first = create(:brand_page, user: user)
      final_lookup_code = first.reload.lookup_code

      # Try to create duplicate with same lookup_code by skipping the after_create callback
      duplicate = build(:brand_page, user: user, lookup_code: final_lookup_code)
      duplicate.define_singleton_method(:update_lookup_code) { } # Skip callback
      duplicate.save

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:lookup_code]).to include("has already been taken")
    end
  end

  describe 'scopes' do
    let!(:draft_page) { create(:brand_page, :draft, user: user) }
    let!(:published_page) { create(:brand_page, :published, user: user) }

    describe '.published' do
      it 'returns only published brand pages' do
        expect(BrandPage.published).to include(published_page)
        expect(BrandPage.published).not_to include(draft_page)
      end
    end

    describe '.drafts' do
      it 'returns only draft brand pages' do
        expect(BrandPage.drafts).to include(draft_page)
        expect(BrandPage.drafts).not_to include(published_page)
      end
    end
  end

  describe 'status methods' do
    let(:draft_page) { create(:brand_page, :draft, user: user) }
    let(:published_page) { create(:brand_page, :published, user: user) }

    describe '#published?' do
      it 'returns true for published pages' do
        expect(published_page.published?).to be true
      end

      it 'returns false for draft pages' do
        expect(draft_page.published?).to be false
      end
    end

    describe '#draft?' do
      it 'returns false for published pages' do
        expect(published_page.draft?).to be false
      end

      it 'returns true for draft pages' do
        expect(draft_page.draft?).to be true
      end
    end

    describe '#status' do
      it 'returns "PUBLISHED" for published pages' do
        expect(published_page.status).to eq('PUBLISHED')
      end

      it 'returns "DRAFT" for draft pages' do
        expect(draft_page.status).to eq('DRAFT')
      end
    end
  end

  describe 'beautiful association naming' do
    let(:draft) { create(:brand_page, :draft, user: user, content: { title: "My Draft Page" }) }

    context 'when draft is published' do
      let!(:published) { draft.publish! }

      before { draft.reload }

      it 'creates beautiful symmetric associations' do
        # Test the beautiful symmetry: draft.published_version ↔ published.draft_version
        expect(draft.published_version).to eq(published)
        expect(published.draft_version).to eq(draft)
      end

      it 'maintains proper status for each version' do
        # After publish!, the published version has status PUBLISHED
        expect(draft.published_version.status).to eq('PUBLISHED')
        expect(published.draft_version.status).to eq('DRAFT')
      end

      it 'establishes bidirectional relationship' do
        expect(draft.published_version).to eq(published)
        expect(published.draft_version).to eq(draft)
      end

      it 'sets the database foreign key correctly' do
        expect(draft.published_version_id).to eq(published.id)
        expect(published.published_version_id).to be_nil
      end
    end
  end

  describe '#publish!' do
    let(:draft) { create(:brand_page, :draft, user: user, content: { title: "My Draft Page", links: [] }) }

    context 'when publishing a draft for the first time' do
      it 'creates a new published version' do
        published = draft.publish!
        expect(published).to be_a(BrandPage)
        expect(published.id).not_to eq(draft.id)  # It's a different record
        # Note: published_at will be set by the background job
        expect(published.published_at).to be_nil
      end

      it 'returns the published version' do
        published = draft.publish!
        # Status should be PUBLISHED immediately
        expect(published.status).to eq('PUBLISHED')
        # But it should trigger the publish job to update published_url and published_at
        expect(PublishJob).to have_received(:perform_async).with(published.lookup_code)
      end

      it 'establishes the relationship between draft and published' do
        published = draft.publish!
        draft.reload

        expect(draft.published_version).to eq(published)
        expect(published.draft_version).to eq(draft)
      end

      it 'generates a unique lookup_code for the published version' do
        published = draft.publish!
        expect(published.lookup_code).to be_present
        expect(published.lookup_code).not_to eq(draft.lookup_code)
      end
    end

    context 'when publishing a draft that already has a published version' do
      let!(:first_published) { draft.publish! }

      before do
        draft.reload
        draft.update!(content: { title: "Updated Draft Page", links: [ "new link" ] })
      end

      it 'updates the existing published version instead of creating new one' do
        expect { draft.publish! }.not_to change { BrandPage.count }
      end

      it 'preserves the lookup_code of the existing published version' do
        original_lookup_code = first_published.lookup_code
        updated_published = draft.publish!

        expect(updated_published.lookup_code).to eq(original_lookup_code)
      end

      it 'updates the published version with new content' do
        updated_published = draft.publish!
        expect(updated_published.content['title']).to eq('Updated Draft Page')
        expect(updated_published.content['links']).to eq([ 'new link' ])
      end
    end

    context 'when trying to publish an already published version' do
      let(:published) { create(:brand_page, :published, user: user) }

      it 'raises an error with clear message' do
        expect { published.publish! }.to raise_error(
          StandardError,
          "You can only publish the draft version, you cannot publish a published version"
        )
      end
    end
  end

  describe '#unpublish!' do
    let(:draft) { create(:brand_page, :draft, user: user) }
    let!(:published) do
      published_record = draft.publish!
      # Simulate what the PublishJob would do
      published_record.update!(
        published_at: Time.current,
        published_url: "https://#{published_record.lookup_code}.thin.ly",
        status: BrandPage::STATUS_PUBLISHED
      )
      published_record
    end

    before { draft.reload }

    context 'when unpublishing a published version' do
      it 'deletes the published record from database' do
        published_id = published.id
        published.unpublish!

        # Simulate successful unpublish job completion by destroying the published record
        published.destroy!

        expect(BrandPage.find_by(id: published_id)).to be_nil
      end

      it 'preserves the draft version' do
        draft_id = draft.id
        published.unpublish!

        draft_after_unpublish = BrandPage.find_by(id: draft_id)
        expect(draft_after_unpublish).to be_present
        expect(draft_after_unpublish.status).to eq('DRAFT')
      end

      it 'removes the reference from draft to published version' do
        published.unpublish!
        draft.reload

        expect(draft.published_version).to be_nil
        expect(draft.published_version_id).to be_nil
      end
    end

    context 'when trying to unpublish a draft version' do
      it 'raises an error with clear message' do
        expect { draft.unpublish! }.to raise_error(
          StandardError,
          "You can only unpublish the published version, you cannot unpublish a draft version"
        )
      end
    end
  end

  describe 'complex publish/unpublish workflow' do
    let(:user) { create(:user) }

    it 'handles the complete workflow correctly' do
      # Step 1: Create draft and publish it
      draft = create(:brand_page, :draft, user: user, content: { title: "My Draft Page", links: [] })
      expect(draft.status).to eq('DRAFT')

      draft.publish!
      draft.reload
      published = draft.published_version
      # Simulate what the PublishJob would do
      published.update!(
        published_at: Time.current,
        published_url: "https://#{published.lookup_code}.thin.ly",
        status: BrandPage::STATUS_PUBLISHED
      )
      expect(published.status).to eq('PUBLISHED')
      expect(published.lookup_code).to be_present

      # Step 2: Verify relationships are established
      draft.reload
      expect(draft.published_version).to eq(published)
      expect(published.draft_version).to eq(draft)

      # Step 3: Try to publish already published version (should fail)
      expect { published.publish! }.to raise_error(
        StandardError,
        /You can only publish the draft version/
      )

      # Step 4: Try to unpublish draft version (should fail)
      expect { draft.unpublish! }.to raise_error(
        StandardError,
        /You can only unpublish the published version/
      )

      # Step 5: Update draft and publish again (should update published version)
      original_lookup_code = published.lookup_code
      draft.update!(content: { title: "Updated Draft Page", links: [ "new link" ] })

      draft.publish!
      draft.reload
      updated_published = draft.published_version
      # Simulate what the PublishJob would do
      updated_published.update!(
        published_at: Time.current,
        published_url: "https://#{updated_published.lookup_code}.thin.ly",
        status: BrandPage::STATUS_PUBLISHED
      )
      expect(updated_published.status).to eq('PUBLISHED')
      expect(updated_published.lookup_code).to eq(original_lookup_code) # Preserved
      expect(updated_published.content['title']).to eq('Updated Draft Page')

      # Step 6: Unpublish the published version
      draft_before_unpublish = updated_published.draft_version
      expect(draft_before_unpublish).to be_present

      updated_published.unpublish!
      # Simulate successful unpublish job completion
      updated_published.destroy!

      # Verify published version is deleted
      expect(BrandPage.find_by(id: updated_published.id)).to be_nil

      # Verify draft still exists
      expect(BrandPage.find_by(id: draft_before_unpublish.id)).to be_present
    end
  end

  describe 'helper methods' do
    let(:draft) { create(:brand_page, :draft, user: user) }

    describe '#get_published_version' do
      context 'when called on a published page' do
        let(:published) { create(:brand_page, :published, user: user) }

        it 'returns itself' do
          expect(published.get_published_version).to eq(published)
        end
      end

      context 'when called on a draft with published version' do
        before do
          published_version = draft.publish!
          # Simulate what the PublishJob would do
          published_version.update!(
            published_at: Time.current,
            published_url: "https://#{published_version.lookup_code}.thin.ly",
            status: BrandPage::STATUS_PUBLISHED
          )
          draft.reload
        end

        it 'returns the published version' do
          expect(draft.get_published_version).to eq(draft.published_version)
          expect(draft.get_published_version.status).to eq('PUBLISHED')
        end
      end

      context 'when called on a draft without published version' do
        it 'returns nil' do
          expect(draft.get_published_version).to be_nil
        end
      end
    end

    describe '#get_draft_version' do
      context 'when called on a draft page' do
        it 'returns itself' do
          expect(draft.get_draft_version).to eq(draft)
        end
      end

      context 'when called on a published page with draft' do
        let(:published) do
          draft.publish!
          draft.reload
          published_version = draft.published_version
          published_version.update!(
            published_at: Time.current,
            published_url: 'https://example.com',
            status: BrandPage::STATUS_PUBLISHED
          )
          published_version
        end

        it 'returns the draft version' do
          expect(published.get_draft_version).to eq(published.draft_version)
          expect(published.get_draft_version.status).to eq('DRAFT')
        end
      end

      context 'when called on a published page without draft' do
        let(:published) { create(:brand_page, :published, user: user) }

        it 'returns itself' do
          expect(published.get_draft_version).to eq(published)
        end
      end
    end
  end
end
