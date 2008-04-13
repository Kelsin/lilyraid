class Signup < ActiveRecord::Base
    belongs_to :raid
    belongs_to :character

    has_many :signup_roles, :dependent => :destroy
    has_many :roles, :through => :signup_roles

    has_one :slot, :dependent => :nullify

    def date
        created_at
    end
end
