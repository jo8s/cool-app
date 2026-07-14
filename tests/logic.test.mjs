// Zero-dependency tests for index.html: structural sanity + coat-logic
// correctness. Run with: node tests/logic.test.mjs
import fs from "node:fs";

const html = fs.readFileSync(new URL("../index.html", import.meta.url), "utf8");
let fails = 0;
const check = (name, cond) => {
  console.log(`  ${cond ? "✓" : "✗"} ${name}`);
  if (!cond) fails++;
};

console.log("Structure:");
for (const id of ["verdict", "reason", "city", "geo", "details", "emoji"]) {
  check(`has #${id}`, html.includes(`id="${id}"`));
}
check("calls Open-Meteo forecast", html.includes("api.open-meteo.com/v1/forecast"));
check("uses geocoding API", html.includes("geocoding-api.open-meteo.com"));
check("uses feels-like (apparent_temperature)", html.includes("apparent_temperature"));
check("reads rain probability", html.includes("precipitation_probability"));
check("requests is_day + uv for night mode & accessories", html.includes("is_day") && html.includes("uv_index"));
check("has weather-fx layer", html.includes('id="fx"'));
check("has accessories row", html.includes('id="extras"'));
check("has hourly strip", html.includes('id="hours"') && /renderHours/.test(html));
check("hourly strip shows actual temp on tap/hover", html.includes("werkelijk ${Math.round(h.actual)}"));
check("requests hourly temp + code for the strip", html.includes("hourly=temperature_2m,apparent_temperature,weather_code"));
check("has geolocation", html.includes("navigator.geolocation"));
check("reverse-geocodes GPS to a place name", html.includes("nominatim") && /reverseGeocode/.test(html));
check("fills the search box from geolocation", /\$\("city"\)\.value\s*=/.test(html));
check("lang is Dutch", html.includes('lang="nl"'));

// Extract the pure-logic block and evaluate it in isolation.
const start = html.indexOf("const LEVELS");
const end = html.indexOf("// ---------- UI wiring");
check("logic block present", start !== -1 && end !== -1 && end > start);
const code = html.slice(start, end);
const { decide, phrase, LEVELS, accessories } = new Function(
  code + "\nreturn { decide, phrase, LEVELS, accessories };"
)();

console.log("\nCoat logic (level: 0 geen jas … 4 blijf binnen):");
const cases = [
  { n: "hot 28°",        in: { feels: 28, temp: 29, wind: 8,  weatherCode: 0,  rainSoonProb: 0 },  level: 0, umbrella: false },
  { n: "mild 16°",       in: { feels: 16, temp: 17, wind: 10, weatherCode: 2,  rainSoonProb: 10 }, level: 1 },
  { n: "cool 11°",       in: { feels: 11, temp: 13, wind: 12, weatherCode: 3,  rainSoonProb: 20 }, level: 2 },
  { n: "rain now 9°",    in: { feels: 9,  temp: 11, wind: 15, weatherCode: 63, rainSoonProb: 90 }, level: 2, umbrella: true },
  { n: "rain soon 12°",  in: { feels: 12, temp: 13, wind: 14, weatherCode: 1,  rainSoonProb: 70 }, level: 2, umbrella: true },
  { n: "snow -2°",       in: { feels: -2, temp: 0,  wind: 10, weatherCode: 73, rainSoonProb: 20 }, level: 3 },
  { n: "freezing -8°",   in: { feels: -8, temp: -4, wind: 20, weatherCode: 0,  rainSoonProb: 0 },  level: 4 },
];
for (const c of cases) {
  const d = decide(c.in);
  check(`${c.n} -> ${LEVELS[c.level].label}`, d.level === c.level);
  if ("umbrella" in c) check(`${c.n} -> umbrella=${c.umbrella}`, d.umbrella === c.umbrella);
  const p = phrase(d);
  check(`${c.n} -> phrase non-empty`, typeof p === "string" && p.length > 0);
}

// Invariant: level is always within range.
check("levels within 0..4", cases.every((c) => decide(c.in).level >= 0 && decide(c.in).level <= 4));

console.log("\nDay-ahead nuance (category change):");
// Cold morning (jas), warm afternoon crossing to geen-jas -> "geen jas meer nodig"
{
  const d = decide({ feels: 10, temp: 11, wind: 5, weatherCode: 0, rainSoonProb: 0,
    outlook: { maxFeels: 22, maxHour: "15:00", maxInHours: 6, minFeels: 9, minHour: "07:00", minInHours: 1 } });
  const p = phrase(d);
  check("warmer -> mentions 'Over 6 uur'", p.includes("Over 6 uur"));
  check("warmer -> mentions rond 15:00", p.includes("15:00"));
  check("warmer -> 'geen jas meer nodig'", p.includes("geen jas meer nodig"));
}
// Cool now (jas, 8°), later only vestje-weather (15°) -> "een vestje al genoeg"
{
  const d = decide({ feels: 8, temp: 9, wind: 5, weatherCode: 0, rainSoonProb: 0,
    outlook: { maxFeels: 15, maxHour: "16:00", maxInHours: 8, minFeels: 8, minHour: "08:00", minInHours: 1 } });
  const p = phrase(d);
  check("warmer -> 'een vestje al genoeg'", p.includes("een vestje al genoeg"));
}
// Warm now (geen jas, 20°), cold evening (jas, 10°) -> "een jas nodig"
{
  const d = decide({ feels: 20, temp: 21, wind: 5, weatherCode: 0, rainSoonProb: 0,
    outlook: { maxFeels: 21, maxHour: "14:00", maxInHours: 2, minFeels: 10, minHour: "21:00", minInHours: 11 } });
  const p = phrase(d);
  check("colder -> 'Over 11 uur' + 'een jas nodig'", p.includes("Over 11 uur") && p.includes("een jas nodig"));
}
// Same category all day -> no nuance
{
  const d = decide({ feels: 15, temp: 16, wind: 5, weatherCode: 0, rainSoonProb: 0,
    outlook: { maxFeels: 16, maxHour: "15:00", maxInHours: 5, minFeels: 14, minHour: "20:00", minInHours: 9 } });
  const p = phrase(d);
  check("stable category -> no nuance", !p.includes("Over "));
}
// Backward-compat: no outlook -> no nuance, no crash
check("no outlook -> no nuance", !phrase(decide(cases[0].in)).includes("Over "));

console.log("\nAccessories:");
{
  const icons = (feels, snow, umbrella, uv) => accessories(feels, { snow }, umbrella, uv).map(a => a.icon);
  check("hot + high UV -> shorts, sunscreen, sunglasses", (() => {
    const a = icons(26, false, false, 7);
    return a.includes("🩳") && a.includes("🧴") && a.includes("🕶️");
  })());
  check("rain -> umbrella", icons(12, false, true, 1).includes("☔"));
  check("freezing -> scarf + gloves", (() => {
    const a = icons(-5, false, false, 0);
    return a.includes("🧣") && a.includes("🧤");
  })());
  check("snow -> snowman", icons(-1, true, false, 0).includes("⛄"));
  check("mild & dry -> no accessories", icons(15, false, false, 1).length === 0);
}

console.log(fails ? `\n❌ FAILED (${fails} check${fails > 1 ? "s" : ""})` : "\n✅ All tests passed.");
process.exit(fails ? 1 : 0);
