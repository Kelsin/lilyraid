class Raid < ActiveRecord::Base
  belongs_to :account
  belongs_to :instance
  belongs_to :list

  has_many :raider_tags
  has_many :tags, :through => :raider_tags

  has_many :locations
  accepts_nested_attributes_for(:locations, :allow_destroy => true,
                                :reject_if => proc { |attr|
                                  attr['instance_id'].blank?
                                })
  has_many :instances, :through => :locations
  has_many :loots, :through => :locations

  before_save :apply_number_of_slots

  has_many :slots, :dependent => :destroy

  has_many :signups, :dependent => :destroy
  has_many :characters, :through => :signups

  has_many :logs

  scope :past, lambda { where('raids.date < ?', Date.today) }
  scope :last_month, lambda { where('raids.date >= ?', Date.today - 1.month) }
  scope :last_three_months, lambda { where('raids.date >= ?', Date.today - 3.months) }
  scope :in_instance, lambda { |instance| where(:instance_id => instance) }

  Inf = 1/0.0

  def to_s
    self.name
  end

  # Validation
  validates_presence_of :name

  def started?
    Time.now > self.date
  end

  def number_of_slots
    self.slots.size || 10
  end

  def number_of_slots=(num)
    @number_of_slots = case num
                       when String
                         num.to_i
                       else
                         num
                       end
  end

  def date=(date)
    case date
    when String
      write_attribute(:date, Time.parse(date))
    else
      write_attribute(:date, date)
    end
  end        

  def confirmed_characters
    slots.map do |slot|
      if slot.signup
        slot.signup.character
      end
    end.compact
  end

  def accounts
    slots.map do |slot|
      if slot.signup
        slot.signup.character.account
      end
    end.compact
  end

  def character_in_raid(character)
    confirmed_characters.member?(character)
  end

  def waiting_list_by_account
    waiting_list.inject([]) do |list, signup|
      if list.empty?
        [[signup]]
      elsif list.last.first.character.account_id == signup.character.account_id
        list.last << signup
        list
      else
        list << [signup]
      end
    end
  end

  def is_open
    return true

    slots.each do |slot|
      if !slot.closed
        return true
      end
    end

    return false
  end

  def signups_from(account)
    signups.select do |signup|
      signup.character.account == account
    end
  end

  def remove_character(char)
    # Delete the signup_slot_types and signup row
    signup = self.signups.where(:character_id => char).first

    if signup
      date = signup.date
      # Destroy signups, this opens the slots up as well
      Signup.destroy(signup.id)

      # Redo the raid if raid
      resignup(date) unless locked

      return true
    else
      return false
    end
  end

  def find_character(char)
    self.slots.includes(:signup).where(:character_id => char).first
  end

  def resignup(date)
    signups = Signup.where('date >= ?', date).all

    # Delete all slots that are tied to signsup past this date
    signups.each do |signup|
      signup.clear_slots
    end

    # redo all signups that occur on or past this date
    signups.each do |signup|
      place_character(signup)
    end
  end

  def waiting_list
    accounts = slots.map { |slot| slot.signup }.compact.map { |signup| signup.character.account }

    signups.select do |signup|
      !accounts.member?(signup.character.account)
    end
  end

  def place_character(signup)
    self.slots.where('signup_id is null and closed = ?', false).order('cclass_id desc, slot_type_id desc').all.each do |slot|
      if slot.accept_char(signup)
        # This slow will accept this character
        slot.signup = signup
        slot.save
        break;
      end
    end
  end

  def add_waiting_list
    waiting_list.each do |signup|
      place_character(signup)
    end
  end

  def groups
    slots.each_slice(5)
  end

  def can_be_deleted?
    loots.size == 0
  end

  # Used for templates
  def template_id=(template_id)
    return if template_id.blank?

    # Number of slots that this raid has
    number_in_raid = self.slots.count

    # Apply a raid template to this raid
    template = Template.find(template_id)
    number_in_template = template.slots.count

    # Remove some slots from this raid
    self.slots.all[number_in_template..-1].map(&:destroy) if number_in_template < number_in_raid

    template.slots.each_with_index do |slot, index|
      if index < number_in_raid
        raid_slot = self.slots[index]

        # We only care if these slots are different
        if raid_slot != slot
          signup = raid_slot.signup
          raid_slot.update_attributes(slot.attributes)
          raid_slot.raid = self
          raid_slot.template = nil

          # Remove character if there is one that doesn't fit into the template
          if signup and raid_slot.accept(signup)
            raid_slot.signup = signup
          end
        end
      else
        # Easy, just create the new one
        self.slots.build(slot.attributes).template = nil
      end
    end
  end

  def uid
    "raid_#{self.id}@raids.dota-guild.com"
  end

  def word_date
    days = self.date.to_date - Date.today

    case days
    when -Inf..-1
      "In the past"
    when 0
      "Today"
    when 1
      "Tomorrow"
    when 2..days_left_in_week
      "This #{day_name(self.date)}"
    when (days_left_in_week + 1)..(days_left_in_week + 7)
      "Next #{day_name(self.date)}"
    when (days_left_in_week + 8)..days_left_in_month
      "Later this month"
    when (days_left_in_month + 1)..days_left_in_two_months
      "Next month"
    when (days_left_in_two_months + 1)..days_left_in_year
      "Later this year"
    else
      "In the future"
    end
  end

  private

  def day_name(date)
    date.strftime("%A")
  end

  def days_left_in_week
    Date.today.end_of_week - Date.today
  end

  def days_left_in_month
    Date.today.end_of_month - Date.today
  end

  def days_left_in_two_months
    (Date.today + 1.month).end_of_month - Date.today
  end

  def days_left_in_year
    Date.today.end_of_year - Date.today
  end

  def apply_number_of_slots
    # If we have a number of slots set, then apply them
    if @number_of_slots

      # Get the current number of slots
      number_in_raid = self.slots.count

      self.slots.all[@number_of_slots..-1].map(&:destroy) if @number_of_slots < number_in_raid

      (@number_of_slots - number_in_raid).times do
        self.slots.build(:roles => Role::ALL)
      end
    end
  end
end
