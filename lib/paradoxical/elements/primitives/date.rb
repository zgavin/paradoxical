class Paradoxical::Elements::Primitives::Date
  # PDX calendar-aware date primitive. Each instance carries a
  # `Paradoxical::Calendars::*` class that provides month structure
  # and day-count arithmetic (no leap years, Stellaris 30-day months,
  # etc.). `Game.new` sets the active game's calendar as
  # `default_calendar` so parser-built dates inherit the right
  # arithmetic without callers having to thread it through.
  #
  # We deliberately do *not* impersonate stdlib `Date` — arithmetic
  # on stdlib Date can land on Feb 29 (real-world leap day,
  # in-game-invalid) and surface as wrong-day bugs much later. The
  # Paradox calendars are regular enough (no leap years, fixed month
  # lengths) that staying outside stdlib lets us guarantee
  # arithmetic that matches the engine.
  #
  # No range validation at parse time. Real game data ships sentinel
  # dates (`0000.00.00`, `1.0.1`) and Feb 29 dates that the engine
  # accepts; we round-trip those bytes faithfully and only impose
  # calendar semantics on the arithmetic path.

  include Comparable

  class << self
    attr_writer :default_calendar

    def default_calendar
      @default_calendar ||= Paradoxical::Calendars::Calendar365
    end
  end

  attr_reader :year, :month, :day, :calendar

  def initialize value, calendar: self.class.default_calendar
    @value = value.to_s
    @calendar = calendar

    parts = @value.split(".").map(&:to_i)
    raise ArgumentError, "expected YYYY.M.D, got #{@value.inspect}" if parts.length != 3

    @year, @month, @day = parts
  end

  def to_pdx
    @value
  end

  def to_s
    @value
  end

  def dup
    self.class.new(@value, calendar: @calendar)
  end

  def + other
    case other
    when Integer                  then add_days(other)
    when ActiveSupport::Duration  then apply_duration(other)
    else raise TypeError, "no implicit conversion of #{other.class} into #{self.class.name}"
    end
  end

  def - other
    case other
    when Integer                                  then add_days(-other)
    when ActiveSupport::Duration                  then apply_duration(-other)
    when Paradoxical::Elements::Primitives::Date  then day_count - other.day_count
    else raise TypeError, "no implicit conversion of #{other.class} into #{self.class.name}"
    end
  end

  def <=> other
    return nil unless other.is_a?(Paradoxical::Elements::Primitives::Date)

    [@year, @month, @day] <=> [other.year, other.month, other.day]
  end

  def == other
    other.is_a?(Paradoxical::Elements::Primitives::Date) and
      @year == other.year and @month == other.month and @day == other.day and
      @calendar == other.calendar
  end

  def eql? other
    self == other
  end

  def hash
    [@year, @month, @day, @calendar].hash
  end

  protected

  def day_count
    @calendar.to_day_count(@year, @month, @day)
  end

  private

  def add_days n
    # `to_i` truncates fractional days at the day-resolution
    # boundary. `ActiveSupport::Duration` parts can be Float
    # (`1.5.days`, `0.5.hours`) and the seconds-to-days conversion
    # in `apply_duration` also produces Float; without truncation
    # those Floats flow through `from_day_count` and produce a
    # Float year/day_of_year, ending in garbage date strings.
    y, m, d = @calendar.from_day_count(day_count + n.to_i)
    self.class.new("#{y}.#{m}.#{d}", calendar: @calendar)
  end

  # Apply a parts-shaped ActiveSupport::Duration:
  #   years/months  — calendar-aware (year+1, month+1 clamped to new month's length)
  #   weeks/days    — converted to absolute days via the calendar
  #   hours/minutes/seconds — truncated to whole days (we're day-resolution)
  def apply_duration dur
    parts = dur.parts
    y, m, d = @year, @month, @day

    y += parts[:years] if parts[:years]

    if parts[:months] then
      total_months_zero_indexed = (m - 1) + parts[:months]
      year_shift, m_zero_indexed = total_months_zero_indexed.divmod(12)
      y += year_shift
      m = m_zero_indexed + 1
      d = [d, @calendar.days_in_month(m)].min
    end

    intermediate = self.class.new("#{y}.#{m}.#{d}", calendar: @calendar)

    extra_days = 0
    extra_days += parts[:weeks] * 7 if parts[:weeks]
    extra_days += parts[:days] if parts[:days]
    seconds = (parts[:hours] || 0) * 3600 + (parts[:minutes] || 0) * 60 + (parts[:seconds] || 0)
    extra_days += seconds / 86400

    extra_days.zero? ? intermediate : intermediate.send(:add_days, extra_days)
  end
end
