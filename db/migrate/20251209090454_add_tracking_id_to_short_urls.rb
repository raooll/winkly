class AddTrackingIdToShortUrls < ActiveRecord::Migration[8.0]
  def change
    add_column :short_urls, :tracking_id, :string
    add_index :short_urls, :tracking_id, unique: true
  end
end
