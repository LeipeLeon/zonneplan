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

  describe "HANDLING_FEE_RAW constant" do
    it "is in the same raw scale as Zonneplan handling fee (~2 ct/kWh)" do
      expect(Zonneplan::HANDLING_FEE_RAW).to be_a(Integer)
      expect(Zonneplan.display_price(Zonneplan::HANDLING_FEE_RAW)).to be_between(1, 5)
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

  # Trimmed copy of the real Flight chunk. "hours" deliberately precedes
  # "quarters" so array ordering cannot accidentally satisfy "quarters win".
  let(:flight_chunk) do
    %q{{"energyData":{"electricity":{"hours":[{"dateTime":"2026-08-03T21:00:00.000000Z","marketPrice":1577700,"priceInclHandlingVat":2109017,"priceEnergyTaxes":1108481,"priceTotalTaxIncluded":3217498,"priceCbsAverage":0.4,"pricingProfile":"normal"}],"quarters":[{"dateTime":"2026-08-03T21:45:00.000000Z","marketPrice":1469399,"priceInclHandlingVat":1977972,"priceEnergyTaxes":1108481,"priceTotalTaxIncluded":3086453,"priceCbsAverage":0.4,"pricingProfile":"normal"},{"dateTime":"2026-08-03T21:30:00.000000Z","marketPrice":1563199,"priceInclHandlingVat":2091470,"priceEnergyTaxes":1108481,"priceTotalTaxIncluded":3199951,"priceCbsAverage":0.4,"pricingProfile":"normal"}],"months":[]},"gas":{"days":[{"dateTime":"2026-08-03T04:00:00.000000Z","priceTotalTaxIncluded":1502345}],"months":[]}}}}
  end

  describe ".extract_price_entries" do
    it "returns the quarters entries, newest first" do
      entries = Zonneplan.extract_price_entries(flight_chunk, "quarters")
      expect(entries.length).to eq(2)
      expect(entries.first["dateTime"]).to eq("2026-08-03T21:45:00.000000Z")
      expect(entries.last["dateTime"]).to eq("2026-08-03T21:30:00.000000Z")
    end

    it "returns the hours entries when asked for hours" do
      entries = Zonneplan.extract_price_entries(flight_chunk, "hours")
      expect(entries.length).to eq(1)
      expect(entries.first["dateTime"]).to eq("2026-08-03T21:00:00.000000Z")
    end

    it "returns nil for an absent key" do
      expect(Zonneplan.extract_price_entries(flight_chunk, "minutes")).to be_nil
    end

    it "returns nil when the value is a Flight reference instead of an array" do
      expect(Zonneplan.extract_price_entries(%q{{"quarters":"$L52"}}, "quarters")).to be_nil
    end
  end

  describe ".parse_price_entries" do
    it "prefers the 15-minute quarters over the 60-minute hours" do
      html = %Q{<script>self.__next_f.push([1,#{JSON.generate(flight_chunk)}])</script>}
      entries = Zonneplan.parse_price_entries(html)
      expect(entries.length).to eq(2)
      gap = Time.parse(entries.first["dateTime"]) - Time.parse(entries.last["dateTime"])
      expect(gap).to eq(900)
    end

    it "returns nil when no chunk carries price data" do
      html = %Q{<script>self.__next_f.push([1,#{JSON.generate(%q{{"seo":{"title":"prijzen"}}})}])</script>}
      expect(Zonneplan.parse_price_entries(html)).to be_nil
    end
  end

  describe ".generate_data_file" do
    require "tempfile"

    # Top of the next hour: hourly data always sits on the hour, and the tick
    # label now depends on it. Deterministic without freezing time.
    let(:next_hour) do
      base = Time.now.localtime + 3600
      base - (base.min * 60 + base.sec)
    end

    def quarter_entry(time, total)
      { "dateTime" => time.iso8601,
        "priceTotalTaxIncluded" => total,
        "pricingProfile" => "normal" }
    end

    it "writes LABEL TOTAL COLOR [BOUNDARY] rows" do
      entries = [quarter_entry(next_hour, 2_636_093)]
      Tempfile.create("hours.dat") do |f|
        Zonneplan.generate_data_file(entries, f.path)
        tokens = File.read(f.path).lines.first.strip.split(/\s+/)
        expect(tokens.length).to eq(4)
        label, total, color, boundary = tokens
        expect(label).to eq(next_hour.strftime("%H"))
        expect(total).to eq("26")
        expect(color).to eq("0x666666")
        expect(boundary).to eq("26.4")
      end
    end

    it "plots the tax-included total, not the market/handling/tax split" do
      entries = [
        { "dateTime" => next_hour.iso8601,
          "priceTotalTaxIncluded" => 2_636_093,
          "marketPrice" => 997_900,
          "priceInclHandlingVat" => 1_407_459,
          "priceEnergyTaxes" => 1_228_634,
          "pricingProfile" => "normal" }
      ]
      Tempfile.create("hours.dat") do |f|
        Zonneplan.generate_data_file(entries, f.path)
        tokens = File.read(f.path).lines.first.strip.split(/\s+/)
        expect(tokens.length).to eq(4)
        expect(tokens[1]).to eq("26")
      end
    end

    it "labels the x-axis only on the hour for 15-minute entries" do
      # Zonneplan ships entries newest first; generate_data_file reverses them.
      entries = [45, 30, 15, 0].map { quarter_entry(next_hour + (_1 * 60), 2_636_093) }
      Tempfile.create("hours.dat") do |f|
        Zonneplan.generate_data_file(entries, f.path)
        labels = File.read(f.path).lines.map { _1.split(/\s+/).first }
        expect(labels).to eq([next_hour.strftime("%H"), %q{""}, %q{""}, %q{""}])
      end
    end

    it "labels exactly one cheapest and one priciest entry" do
      totals = [1_300_000, 1_300_000, 3_700_000, 3_700_000]
      entries = [0, 15, 30, 45].map.with_index { |min, i| quarter_entry(next_hour + (min * 60), totals[i]) }.reverse
      Tempfile.create("hours.dat") do |f|
        Zonneplan.generate_data_file(entries, f.path)
        rows = File.read(f.path).lines.map { _1.strip.split(/\s+/) }
        expect(rows.count { _1.size == 4 }).to eq(2)
        expect(rows.select { _1.size == 4 }.map(&:last)).to eq(["13.0", "37.0"])
      end
    end

    it "keeps an hour label on every row for hourly entries" do
      entries = [quarter_entry(next_hour + 3600, 2_700_000), quarter_entry(next_hour, 2_636_093)]
      Tempfile.create("hours.dat") do |f|
        Zonneplan.generate_data_file(entries, f.path)
        labels = File.read(f.path).lines.map { _1.split(/\s+/).first }
        expect(labels).to all(match(/\A\d{2}\z/))
      end
    end
  end
end
