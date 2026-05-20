# Zonneplan → TRMNL

Generates an e-ink-ready image of Zonneplan's hourly dynamic electricity prices for the [TRMNL](https://usetrmnl.com/) display. Use the rendered PNG/BMP with the TRMNL [Image display](https://usetrmnl.com/plugin_settings?keyname=image_display) or [Alias](https://usetrmnl.com/plugin_settings?keyname=alias) plugin.

![](https://leipeleon.github.io/zonneplan/diffused.png)

## Published outputs

The hourly GitHub Actions workflow publishes the latest images to GitHub Pages:

- Color chart: <https://leipeleon.github.io/zonneplan/hours.png>
- Dithered PNG: <https://leipeleon.github.io/zonneplan/dithered.png>
- 1-bit PNG (for TRMNL): <https://leipeleon.github.io/zonneplan/diffused.png>
- 1-bit BMP (for TRMNL): <https://leipeleon.github.io/zonneplan/diffused.bmp>
- Rendered README: <https://leipeleon.github.io/zonneplan/>

## How it works

1. **Fetch.** Scrape <https://www.zonneplan.nl/energie/dynamische-energieprijzen>, scanning the streamed Next.js chunks (`self.__next_f.push([...])`) for `ElectricityHour` objects.
2. **Fallback.** If no `ElectricityHour` records turn up, fall back to the EnergyZero public API (`https://api.energyzero.nl/v1/energyprices`). Pricing profile (`low` / `normal` / `high`) is then classified by quartile bucketing across the day's prices.
3. **Tabulate.** Write a gnuplot data file with the price split into stacked components — market price, handling fee, energy taxes — plus the profile color and a label on the day's min/max boundary hours. Past hours (older than ~1h) are greyed out; anything older than 4h is dropped.
4. **Plot.** Render an 800×480 PNG via gnuplot — that's the TRMNL display resolution.
5. **Dither.** Run it through ImageMagick: Floyd–Steinberg + ordered dither → 1-bit monochrome PNG and BMP.

Raw price fields (`priceTotalTaxIncluded`, `marketPrice`, `priceEnergyTaxes`, `priceInclHandlingVat`) are integers; divide by `Zonneplan::PRICE_DIVISOR` (`100_000`) to get EUR/kWh.

## Automation

`.github/workflows/build.yml` runs on push to `main`, PRs, manual dispatch, and an hourly cron (`5 * * * *`). Each run:

- Installs `gnuplot-nox` + `imagemagick` (apt archives cached between runs).
- Executes `./script/build`.
- Renders this README via the GitHub Markdown API into `build/index.html`.
- Archives `hours.png` and `hours.dat` under `history/YYYY/MM/DD-HHMM*` and commits the snapshot back to `main`.
- Deploys `build/` to GitHub Pages.

## Running locally

Prerequisites:

```sh
brew install gnuplot imagemagick    # Ruby 3.3 also required
```

Then:

```sh
./script/build
```

Outputs land in `build/`. The script forces `TZ=Europe/Amsterdam` so the chart aligns with Dutch wall-clock time regardless of host TZ.

## Tests

```sh
bundle exec rspec
```

RSpec + WebMock with fixtures under `spec/fixtures/`.

## Further reading

- <https://help.usetrmnl.com/en/articles/11479051-image-display>
- <https://docs.usetrmnl.com/go/imagemagick-guide>
- <https://usage.imagemagick.org/crop/#crop>
