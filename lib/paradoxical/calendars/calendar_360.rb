# 12 months × 30 days = 360-day Stellaris calendar. Every month has
# 30 days exactly; `2200.2.30` is a valid in-game date stdlib `Date`
# can't even represent. Same shape as `Calendar365` — `to_day_count`
# / `from_day_count` are inverses across the full integer range. No
# range validation at construction, see `Calendar365` for rationale.
class Paradoxical::Calendars::Calendar360
  MONTH_LENGTH = 30
  MONTHS_PER_YEAR = 12
  DAYS_PER_YEAR = MONTHS_PER_YEAR * MONTH_LENGTH

  class << self
    def days_in_month _month
      MONTH_LENGTH
    end

    def days_in_year _year
      DAYS_PER_YEAR
    end

    def to_day_count year, month, day
      (year - 1) * DAYS_PER_YEAR + (month - 1) * MONTH_LENGTH + (day - 1)
    end

    def from_day_count count
      year, rest = count.divmod(DAYS_PER_YEAR)
      year += 1
      month, day = rest.divmod(MONTH_LENGTH)
      [year, month + 1, day + 1]
    end
  end
end
