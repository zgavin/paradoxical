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

  describe "EU4 variable-method override" do
    # EU4's set_variable/check_variable etc. emit `which = NAME`
    # (instead of `value = NAME`) when the second operand is a
    # non-numeric reference to another variable. The base Builder
    # implementation always uses `value`; the EU4::DSL override
    # swaps to `which` for non-numerics.

    let(:base_builder)    { Paradoxical::Builder.new }
    let(:eu4_builder)     { builder_with(Paradoxical::Games::EU4::DSL) }

    it "base Builder always uses `value` as the second key" do
      elements = base_builder.build { set_variable "gold", "=", "other_var" }
      list = elements.first
      expect(list[1].key.to_s).to eq("value")
    end

    it "EU4 swaps to `which` when the value is a non-numeric reference" do
      elements = eu4_builder.build { set_variable "gold", "=", "other_var" }
      list = elements.first
      expect(list[1].key.to_s).to eq("which")
    end

    it "EU4 keeps `value` when the value is numeric" do
      elements = eu4_builder.build { set_variable "gold", "=", 100 }
      list = elements.first
      expect(list[1].key.to_s).to eq("value")
    end

    it "EU4 doesn't override export_to_variable (always emits `value`)" do
      # Base implementation; EU4::DSL's override loop excludes
      # `export_to_variable` because it has its own dedicated method
      # in Builder with a different shape (which/value/who triplet).
      elements = eu4_builder.build { export_to_variable "gold", "treasury" }
      list = elements.first
      expect(list.key.to_s).to eq("export_to_variable")
      keys = list.map { |c| c.key.to_s }
      expect(keys).to eq(%w[which value])
    end
  end
end
