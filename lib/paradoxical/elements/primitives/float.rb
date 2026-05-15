class Paradoxical::Elements::Primitives::Float
  include Paradoxical::Elements::Concerns::Impersonator

  # Backed by `BigDecimal`, not Ruby's binary `::Float`. Empirical
  # sweep (EU5) shows game-data floats carry 4-6 digits of precision
  # (with 6 a soft limit — ~20k 6-digit values, only 49 with 7+
  # across the install). Binary FP loses precision on the very
  # values modders care about for DSL math; `BigDecimal` preserves
  # them by construction.
  #
  # **In-game empirical confirmation (EU5).** Validated against the
  # actual engine via a console `run` script:
  #
  #   set_local_variable = { name = test_var value = 0.2 }
  #   while = { count = 10 change_local_variable = { name = test_var add = 0.1 } }
  #   debug_log = "test_var: [SCOPE.GetLocalVariable('test_var').GetValue]"
  #
  # Result: `1.2` cleanly (not `1.2000000476…` or other binary-FP
  # drift). So the engine isn't using `Float`/`double` for variable
  # arithmetic — it's fixed-precision or BigDecimal-equivalent.
  # Either way, the BigDecimal Ruby-side model is correct.
  #
  # Same probe also revealed two precision caps:
  # - **6 digits** for general-position values (source-file constants
  #   in modifiers / events / etc.). Beyond that → load-time errors.
  # - **5 digits** specifically for `set_local_variable` /
  #   `change_local_variable`. Distinct error messages for the two
  #   operations suggests they're separately validated, not a shared
  #   parser path. So a 6-digit constant in `modifiers.txt` loads
  #   fine but feeding the same value via `change_local_variable add`
  #   errors. Practical implication for the DSL: stay ≤5 digits in
  #   emitted variable arithmetic; ≤6 elsewhere.
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
