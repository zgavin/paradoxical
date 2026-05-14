module Paradoxical::Calendars
end

# 12-month, 365-day, no-leap-year calendar. EU4 / EU5 / CK3 / HOI4 /
# Imperator: Rome all use this shape. Not "Gregorian" — Gregorian has
# leap years; this is a Paradox invention with no real-world analog.
# Naming descriptively (Calendar365) instead of historically (Julian /
# Gregorian) keeps that fact visible.
#
# Negative years are accepted as integer math (Imperator's BC dates
# like `-50.1.1` round-trip correctly through `to_day_count` /
# `from_day_count`). No range validation at construction — real game
# data ships sentinel dates (`0000.00.00`, `1.0.1`) and Feb 29 dates
# that the engine accepts; the calendar is an arithmetic engine, not
# a validator.
#
# **Feb 29 → Mar 1 normalization.** EU5 game data includes Feb 29
# dates (`1313.2.29`, `888.2.29`, `1756.2.29` etc.) in characters,
# events, and historical timelines. In-game verification (PR #69
# review) shows the engine renders these as Mar 1 of the same year —
# so a "29th of Feb" in source is an alternative spelling of "1st of
# March." Our day-count math implicitly does the same thing: day 59
# of any year (where Feb's 28 days + 0 indexing leave you) walks
# past Feb's 28-day length and lands on Mar 1 via `from_day_count`.
# That means arithmetic on a parsed Feb 29 — even `date + 0` —
# returns a date whose `to_pdx` is "Y.3.1" rather than "Y.2.29".
# `Primitives::Date#to_pdx` on the *unmutated* parser product still
# emits the raw bytes ("Y.2.29") so the byte-identical round-trip
# property holds; the engine-normalized form is only observable
# after an arithmetic operation, which is the right asymmetry.
#
# `to_day_count` and `from_day_count` are inverses across the full
# integer range. Day 0 is year 1, January 1. Negative days walk back
# through year 0, year -1, etc. (year 0 doesn't exist historically
# but exists mathematically — the year before AD 1).
class Paradoxical::Calendars::Calendar365
  MONTH_LENGTHS = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31].freeze
  DAYS_PER_YEAR = 365

  class << self
    def days_in_month month
      MONTH_LENGTHS[month - 1]
    end

    def days_in_year _year
      DAYS_PER_YEAR
    end

    # (year, month, day) → absolute day count from year 1, January 1 = 0.
    # Linear in year; negative years and out-of-range months/days flow
    # through cleanly so arithmetic on permissively-parsed dates doesn't
    # crash.
    def to_day_count year, month, day
      days_before_month = MONTH_LENGTHS[0, month - 1].sum
      (year - 1) * DAYS_PER_YEAR + days_before_month + (day - 1)
    end

    # Inverse of `to_day_count`. Returns [year, month, day].
    def from_day_count count
      year, day_of_year = count.divmod(DAYS_PER_YEAR)
      year += 1

      MONTH_LENGTHS.each_with_index do |len, idx|
        return [year, idx + 1, day_of_year + 1] if day_of_year < len

        day_of_year -= len
      end

      raise "unreachable: divmod gave day_of_year > DAYS_PER_YEAR for count=#{count}"
    end
  end
end
