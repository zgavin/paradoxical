class Paradoxical::Elements::Primitives::Float
  include Paradoxical::Elements::Concerns::Impersonator

  # Backed by `BigDecimal`, not Ruby's binary `::Float`. Empirical
  # sweep (EU5) shows game-data floats carry 4-6 digits of precision
  # (with 6 a soft limit — ~20k 6-digit values, only 49 with 7+
  # across the install). Binary FP loses precision on the very
  # values modders care about for DSL math; `BigDecimal` preserves
  # them by construction.
  #
  # `Impersonator#to_real` delegates to the raw byte string's
  # `to_d`, so arithmetic and comparisons via
  # `impersonate_infix_methods` operate on BigDecimal values. The
  # raw bytes still round-trip via `to_pdx`; only the *result* of
  # arithmetic changes type (was `::Float`, now `::BigDecimal`).
  impersonate ::BigDecimal, :to_d

  impersonate_infix_methods %i{!~ % * ** + - / =~}

  def coerce something
    case something
    when ::Integer then [@value.to_i, something]
    when ::Float   then [@value.to_f, something]
    else                [@value.to_d, something]
    end
  end
end
