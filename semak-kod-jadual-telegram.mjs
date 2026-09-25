// Semak: kod jadual butang Lulus/Tolak Telegram mesti SAMA dalam dua fungsi Edge
//   - notifikasi-kelulusan-pemilik  (JADUAL_CODE: jadual -> kod)
//   - telegram-webhook              (CODE_JADUAL: kod -> jadual)
// Jalankan sebelum deploy:  node semak-kod-jadual-telegram.mjs
import { readFileSync } from "node:fs";

const salur = (fail, nama) => {
  const src = readFileSync(fail, "utf8");
  const m = src.match(new RegExp(`const ${nama}[^=]*=\\s*\\{([\\s\\S]*?)\\};`));
  if (!m) throw new Error(`${nama} tidak dijumpai dalam ${fail}`);
  return Object.fromEntries([...m[1].matchAll(/(\w+)\s*:\s*"(\w+)"/g)].map((x) => [x[1], x[2]]));
};

const kiriman = salur("supabase/functions/notifikasi-kelulusan-pemilik/index.ts", "JADUAL_CODE");
const webhook = salur("supabase/functions/telegram-webhook/index.ts", "CODE_JADUAL");
const terbalik = Object.fromEntries(Object.entries(webhook).map(([kod, jadual]) => [jadual, kod]));

const a = JSON.stringify(Object.entries(kiriman).sort());
const b = JSON.stringify(Object.entries(terbalik).sort());
if (a !== b) {
  console.error("TIDAK SAMA!\n notifikasi-kelulusan-pemilik:", kiriman, "\n telegram-webhook (terbalik):", terbalik);
  process.exit(1);
}
console.log(`OK: ${Object.keys(kiriman).length} kod jadual sama dalam kedua-dua fungsi.`);
