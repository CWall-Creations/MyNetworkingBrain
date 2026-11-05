class IndustryFit < ApplicationRecord
  def self.score_for(industry) = find_by(industry: industry)&.score
end
