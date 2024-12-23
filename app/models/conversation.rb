class Conversation < ApplicationRecord
  include Version

  belongs_to :user
  belongs_to :assistant

  has_many :messages, dependent: :destroy
  has_many :runs, dependent: :destroy
  has_many :steps, dependent: :destroy
  belongs_to :last_assistant_message, class_name: "Message", inverse_of: :conversation, optional: true

  after_touch :set_title_async, if: -> { title.blank? && messages.count >= 2 }

  scope :ordered, -> { order(updated_at: :desc) }

  broadcasts_refreshes

  # Builds a hash of date interval keys and queries which fetch the records for that internal.
  #
  # Empty intervals are removed from the hash.
  #
  # {
  #  "Today" => relation,
  #  "Yesterday" => relation,
  #  "This Week" => relation,
  #  "This Month" => relation,
  #  "Last Month" => relation,
  #  "Older" => relation
  # }
  def self.grouped_by_increasing_time_interval_for_user(user, query = nil)
    if query.blank?
      nav_conversations = user.conversations.ordered
    else
      nav_conversations = user.conversations.joins(:messages).ordered.where("messages.content_text ILIKE ?", "%#{query}%").
        or(user.conversations.ordered.where("title ILIKE ?", "%#{query}%")).
        select("DISTINCT conversations.*")
    end

    keys = ["Today", "Yesterday", "This Week", "This Month", "Last Month", "Older"]
    values = [
      nil,
      Date.current.beginning_of_day,
      (Date.current - 1.day).beginning_of_day,
      (Date.current - 1.week).beginning_of_day,
      (Date.current - 1.month).beginning_of_day,
      (Date.current - 2.months).beginning_of_day,
      nil
    ].each_cons(2).map do |range_start, range_end|
      range = case
      when range_start.nil?
        range_end..
      when range_end.nil?
        ..range_start
      else
        range_end..range_start
      end

      nav_conversations.where(updated_at: range)
    end

    keys.zip(values)
      .to_h
      .delete_if { |_, v| v.empty? }
  end

  def total_cost
    input_token_total_cost + output_token_total_cost
  end

  private

  def set_title_async
    AutotitleConversationJob.perform_later(id)
  end
end
