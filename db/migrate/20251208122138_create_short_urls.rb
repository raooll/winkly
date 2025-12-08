class CreateShortUrls < ActiveRecord::Migration[7.0]
  def change
    create_table :short_urls do |t|
      t.references :user, null: false, foreign_key: true
      t.text :url1, null: false
      t.text :url2
      t.string :short_uri, null: false
      t.integer :click_count, default: 0

      t.timestamps
    end
    
    add_index :short_urls, :short_uri, unique: true
  end
end