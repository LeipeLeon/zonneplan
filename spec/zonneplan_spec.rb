require_relative "../lib/zonneplan"

RSpec.describe Zonneplan do
  describe ".convert_energyzero_price" do
    it "converts EUR price to the same scale as Zonneplan raw prices" do
      # EnergyZero returns ~0.26 EUR, Zonneplan stores ~2_636_093
      # 0.26 * 10_000_000 = 2_600_000
      expect(Zonneplan.convert_energyzero_price(0.26)).to eq(2_600_000)
    end

    it "rounds to nearest integer" do
      expect(Zonneplan.convert_energyzero_price(0.2636093)).to eq(2_636_093)
    end
  end

  describe ".display_price" do
    it "converts Zonneplan raw price to display cents" do
      # 2_636_093 / 100_000 = 26.36093 -> rounds to 26
      expect(Zonneplan.display_price(2_636_093)).to eq(26)
    end

    it "converts EnergyZero-normalized price to display cents" do
      converted = Zonneplan.convert_energyzero_price(0.26)
      expect(Zonneplan.display_price(converted)).to eq(26)
    end

    it "produces consistent results between both data sources" do
      zonneplan_raw = 2_636_093
      energyzero_eur = 0.2636093

      energyzero_converted = Zonneplan.convert_energyzero_price(energyzero_eur)
      expect(Zonneplan.display_price(energyzero_converted)).to eq(Zonneplan.display_price(zonneplan_raw))
    end
  end

  describe "ENERGY_TAX_RAW constant" do
    it "is in the same raw scale as priceEnergyTaxes from Zonneplan" do
      expect(Zonneplan::ENERGY_TAX_RAW).to be_a(Integer)
      expect(Zonneplan.display_price(Zonneplan::ENERGY_TAX_RAW)).to be_between(10, 15)
    end
  end

  describe ".classify_pricing_profile" do
    let(:prices) { [0.10, 0.15, 0.20, 0.25, 0.30, 0.35, 0.40, 0.45] }

    it "classifies bottom quartile as low" do
      expect(Zonneplan.classify_pricing_profile(0.10, prices)).to eq("low")
      expect(Zonneplan.classify_pricing_profile(0.15, prices)).to eq("low")
    end

    it "classifies top quartile as high" do
      expect(Zonneplan.classify_pricing_profile(0.40, prices)).to eq("high")
      expect(Zonneplan.classify_pricing_profile(0.45, prices)).to eq("high")
    end

    it "classifies middle values as normal" do
      expect(Zonneplan.classify_pricing_profile(0.25, prices)).to eq("normal")
      expect(Zonneplan.classify_pricing_profile(0.30, prices)).to eq("normal")
    end

    it "handles single-element list" do
      expect(Zonneplan.classify_pricing_profile(0.20, [0.20])).to eq("low")
    end
  end

  describe ".generate_data_file" do
    require "tempfile"

    it "writes HOUR PRICE_EX_TAX TAX_AMOUNT COLOR [BOUNDARY] rows" do
      hours = [
        { "dateTime" => (Time.now + 3600).iso8601,
          "priceTotalTaxIncluded" => 3_000_000,
          "priceEnergyTaxes" => 1_228_634,
          "pricingProfile" => "normal" }
      ]
      Tempfile.create("hours.dat") do |f|
        Zonneplan.generate_data_file(hours, f.path)
        tokens = File.read(f.path).lines.first.strip.split(/\s+/)
        expect(tokens.length).to be_between(4, 5)
        hour, price_ex, tax_amt, color, * = tokens
        expect(hour).to match(/\A\d{2}\z/)
        expect(price_ex.to_i + tax_amt.to_i).to be_within(1).of(30)
        expect(tax_amt.to_i).to eq(12)
        expect(color).to start_with("0x")
      end
    end

    it "clamps tax to total when total < energy tax" do
      hours = [
        { "dateTime" => (Time.now + 3600).iso8601,
          "priceTotalTaxIncluded" => 500_000,
          "priceEnergyTaxes" => 1_228_634,
          "pricingProfile" => "low" }
      ]
      Tempfile.create("hours.dat") do |f|
        Zonneplan.generate_data_file(hours, f.path)
        tokens = File.read(f.path).lines.first.strip.split(/\s+/)
        _, price_ex, tax_amt, _ = tokens
        expect(price_ex.to_i).to be >= 0
        expect(price_ex.to_i + tax_amt.to_i).to be_within(1).of(5)
      end
    end
  end
end
