require "paradoxical"

# Per-game DSL helpers live in `Paradoxical::Games::*::DSL` and get
# prepended onto Builder by `paradoxical!` when the matching game is
# active. These tests exercise that wiring directly via anonymous
# Builder subclasses (since prepend is permanent on a class, and we
# don't want one game's prepend to bleed into another's tests).

RSpec.describe "per-game DSL prepended onto Builder" do
  def builder_with(*dsl_modules)
    klass = Class.new(Paradoxical::Builder)
    dsl_modules.each { |m| klass.prepend(m) }
    klass.new
  end

  describe "Stellaris" do
    let(:builder) { builder_with(Paradoxical::Games::Stellaris::DSL) }

    it "exposes add_resource (which Builder alone doesn't have)" do
      expect(Paradoxical::Builder.instance_methods).not_to include(:add_resource)
      expect(builder).to respond_to(:add_resource)
    end

    it "add_resource with a numeric value renders single-line" do
      elements = builder.build { add_resource "energy", 5 }
      list = elements.first
      expect(list.key.to_s).to eq("add_resource")
      expect(list.first.key.to_s).to eq("energy")
      expect(list.first.value.to_s).to eq("5")
    end

    it "add_resource with a string value routes through `mult`" do
      elements = builder.build { add_resource "energy", "monthly_energy" }
      list = elements.first
      expect(list[0].key.to_s).to eq("energy")
      expect(list[0].value.to_s).to eq("1")
      expect(list[1].key.to_s).to eq("mult")
      expect(list[1].value.to_s).to eq("monthly_energy")
    end

    it "check_galaxy_setup_value emits `setting` and `value` properties" do
      elements = builder.build { check_galaxy_setup_value "difficulty", ">=", 2 }
      list = elements.first
      expect(list.key.to_s).to eq("check_galaxy_setup_value")
      expect(list[0].key.to_s).to eq("setting")
      expect(list[1].key.to_s).to eq("value")
      expect(list[1].operator).to eq(">=")
    end
  end

  describe "EU4 variable arithmetic (which/value with non-numeric wrinkle)" do
    # EU4's set_variable/check_variable etc. emit `which = NAME`
    # (instead of `value = NAME`) when the second operand is a
    # non-numeric reference to another variable. Per 5e the legacy
    # family lives on EU4's DSL module (not base Builder anymore).

    let(:eu4_builder) { builder_with(Paradoxical::Games::EU4::DSL) }

    it "swaps to `which` when the value is a non-numeric reference" do
      elements = eu4_builder.build { set_variable "gold", "=", "other_var" }
      list = elements.first
      expect(list[1].key.to_s).to eq("which")
    end

    it "keeps `value` when the value is numeric" do
      elements = eu4_builder.build { set_variable "gold", "=", 100 }
      list = elements.first
      expect(list[1].key.to_s).to eq("value")
    end

    it "export_to_variable always uses `value` (no which-wrinkle)" do
      elements = eu4_builder.build { export_to_variable "gold", "treasury" }
      list = elements.first
      expect(list.key.to_s).to eq("export_to_variable")
      keys = list.map { |c| c.key.to_s }
      expect(keys).to eq(%w[which value])
    end
  end

  describe "Stellaris variable arithmetic (which/value, no wrinkle)" do
    let(:builder) { builder_with(Paradoxical::Games::Stellaris::DSL) }

    it "emits `which`/`value` second-key shape" do
      elements = builder.build { set_variable "score", "=", 5 }
      list = elements.first
      expect(list.key.to_s).to eq("set_variable")
      expect(list[0].key.to_s).to eq("which")
      expect(list[1].key.to_s).to eq("value")
    end

    it "doesn't apply EU4's which-second-key swap for non-numerics" do
      # Stellaris always uses `value` even when the rhs is a reference.
      elements = builder.build { change_variable "score", "=", "other_var" }
      list = elements.first
      expect(list[1].key.to_s).to eq("value")
    end
  end

  describe "HOI4 variable arithmetic (direct key=value shape)" do
    let(:builder) { builder_with(Paradoxical::Games::HOI4::DSL) }

    it "emits the variable name as the inner key" do
      # HOI4 shape: `set_variable = { VAR_NAME = VAL }` — the name is
      # the key of the inner property, no `which =` / `name =` wrapper.
      elements = builder.build { set_variable "morale_buff", "=", 5 }
      list = elements.first
      expect(list.key.to_s).to eq("set_variable")
      expect(list[0].key.to_s).to eq("morale_buff")
      expect(list[0].value.to_i).to eq(5)
    end

    it "uses `add_to_variable` as the arithmetic verb (not change_variable)" do
      elements = builder.build { add_to_variable "morale_buff", "=", 1 }
      list = elements.first
      expect(list.key.to_s).to eq("add_to_variable")
    end
  end

  describe "EU5 / Imperator variable arithmetic (name/value, operation-keyed)" do
    # Same surface in both games today — testing via EU5 since the
    # shape is identical.

    let(:builder) { builder_with(Paradoxical::Games::EU5::DSL) }

    it "set_variable uses `name`/`value` body" do
      elements = builder.build { set_variable "treaty_progress", 50 }
      list = elements.first
      expect(list.key.to_s).to eq("set_variable")
      expect(list[0].key.to_s).to eq("name")
      expect(list[1].key.to_s).to eq("value")
    end

    it "exposes scope-prefixed variants (local / global)" do
      local_elements  = builder.build { set_local_variable "ctx_var", 1 }
      global_elements = builder.build { set_global_variable "world_var", 2 }
      expect(local_elements.first.key.to_s).to eq("set_local_variable")
      expect(global_elements.first.key.to_s).to eq("set_global_variable")
    end

    it "set_variable single-arg form emits property shorthand (5e-3)" do
      # `set_variable("foo")` -> `set_variable = foo`. Empirical: 768
      # uses in EU5 for boolean-flag-style variables; equivalent to
      # `set_variable = { name = foo value = yes }` per the wiki.
      elements = builder.build { set_variable "borgia_pope_global" }
      prop = elements.first
      expect(prop).to be_a(Paradoxical::Elements::Property)
      expect(prop.key.to_s).to eq("set_variable")
      expect(prop.value.to_s).to eq("borgia_pope_global")
    end

    it "property-form shorthand applies to local / global variants too" do
      local_p  = builder.build { set_local_variable  "flag_a" }.first
      global_p = builder.build { set_global_variable "flag_b" }.first
      expect(local_p).to be_a(Paradoxical::Elements::Property)
      expect(global_p).to be_a(Paradoxical::Elements::Property)
      expect(local_p.key.to_s).to eq("set_local_variable")
      expect(global_p.key.to_s).to eq("set_global_variable")
    end

    it "set_variable accepts a `days:` kwarg for variable lifetime (5e-3)" do
      # Real example: `set_variable = { name = ccw_timer value = yes days = 365 }`.
      elements = builder.build { set_variable "ccw_timer", "yes", days: 365 }
      list = elements.first
      expect(list).to be_a(Paradoxical::Elements::List)
      keys = list.map { |c| c.key.to_s }
      expect(keys).to eq(%w[name value days])
    end

    it "`days:` kwarg works for local / global variants" do
      local_l  = builder.build { set_local_variable  "x", 1, days: 30 }.first
      global_l = builder.build { set_global_variable "y", 2, days: 60 }.first
      expect(local_l.map { |c| c.key.to_s }).to eq(%w[name value days])
      expect(global_l.map { |c| c.key.to_s }).to eq(%w[name value days])
    end

    it "change_variable accepts operation kwargs and emits them in order" do
      # `change_variable("imperial_authority_change", max: 0.2, min: 0.01, multiply: 100)`
      # (the EU5 example shape from MODERNIZATION 5e).
      elements = builder.build do
        change_variable "imperial_authority_change", max: 0.2, min: 0.01, multiply: 100
      end
      list = elements.first
      expect(list.key.to_s).to eq("change_variable")
      keys = list.map { |c| c.key.to_s }
      expect(keys).to eq(%w[name max min multiply])
    end

    it "scope variants apply to change_variable too" do
      local_elements  = builder.build { change_local_variable "v", add: 1 }
      global_elements = builder.build { change_global_variable "v", add: 1 }
      expect(local_elements.first.key.to_s).to eq("change_local_variable")
      expect(global_elements.first.key.to_s).to eq("change_global_variable")
    end

    it "change_variable accepts a block for nested operations (5e-2)" do
      # Operations whose value is itself a block of further operations.
      # The block evaluates in Builder context, so any `keyword do ... end`
      # falls through method_missing → pdx_obj and emits the nested shape.
      # EU5 imperial_authority example from MODERNIZATION 5e.
      elements = builder.build do
        change_variable "imperial_authority" do
          add do
            value "scope:loser.total_population"
            divide "scope:winner.total_population"
            max 2
            min 0.1
            multiply 5
          end
        end
      end

      list = elements.first
      expect(list.key.to_s).to eq("change_variable")

      add_node = list["add"]
      expect(add_node).to be_a(Paradoxical::Elements::List)
      add_keys = add_node.map { |c| c.key.to_s }
      expect(add_keys).to eq(%w[value divide max min multiply])
    end

    it "change_variable block form emits multi-line, kwargs form stays single-line" do
      single = builder.build { change_variable "x", add: 5 }.first
      nested = builder.build do
        change_variable "x" do
          add do
            value "y"
            multiply 2
          end
        end
      end.first

      # `single_line!` collapses whitespace; the block form keeps the
      # natural multi-line emission since nested bodies want to
      # render readably. Top-level emission always includes one
      # leading newline (`line_break`); the single-line form has
      # exactly that one, while nested has internal newlines too.
      expect(single.to_pdx.count("\n")).to eq(1)
      expect(nested.to_pdx.count("\n")).to be > 1
    end

    it "change_variable rejects unknown operation kwargs" do
      expect { builder.build { change_variable "x", bogus: 1 } }
        .to raise_error(ArgumentError, /unknown change_variable operation/)
      expect { builder.build { change_variable "x", add: 1, also_bogus: 2 } }
        .to raise_error(ArgumentError, /also_bogus/)
    end

    it "change_variable stays multi-line for multi-op flat kwargs (single_line! only when one op)" do
      one_op   = builder.build { change_variable "x", add: 5 }.first
      multi_op = builder.build { change_variable "x", multiply: 100, min: 0, max: 1 }.first

      # Matches real EU5 source style: single-op changes are inline,
      # multi-op changes are written across lines for readability.
      expect(one_op.to_pdx.count("\n")).to eq(1)
      expect(multi_op.to_pdx.count("\n")).to be > 1
    end

    it "change_variable allows mixing flat kwargs with a block (kwargs first)" do
      elements = builder.build do
        change_variable "x", multiply: 2 do
          add do
            value "y"
          end
        end
      end
      list = elements.first
      keys = list.map { |c| c.respond_to?(:key) ? c.key.to_s : nil }.compact
      # Order: name, then flat kwargs (multiply), then block contents (add)
      expect(keys).to eq(%w[name multiply add])
    end
  end
end
