// Build ANIMATED "word-pop" ASS captions from a transcribe.py transcript slice.
// usage: node ass_from_words.cjs <transcript.json> <startSec> <endSec> <fontName> [maxChars] > out.ass
//
// Word-pop style: single line always (packed by character budget -> never wraps, never
// jumps vertically), anchored at a fixed point (\pos), the currently-spoken word scales
// up + turns yellow. Consecutive captions never overlap (each ends when the next begins).
const fs = require('fs');
const [, , tp, s0, s1, fontName, maxCharsArg] = process.argv;
const start = parseFloat(s0), end = parseFloat(s1);
const MAXCHARS = Math.max(6, parseInt(maxCharsArg || '15', 10));
const MAXWORDS = 3;
const data = JSON.parse(fs.readFileSync(tp, 'utf8'));

let words = (data.words || [])
  .map(w => ({ t: (w.text || '').trim(), a: w.start, b: w.end }))
  .filter(w => w.t && w.b > start && w.a < end)
  .map(w => ({ t: w.t, a: Math.max(0, w.a - start), b: Math.max(0.05, w.b - start) }));
const END = end - start;

const cs = x => { const c = Math.round(Math.max(0, x) * 100); const h = Math.floor(c/360000); const m = Math.floor(c%360000/6000); const s = Math.floor(c%6000/100); const cc = c%100; return `${h}:${String(m).padStart(2,'0')}:${String(s).padStart(2,'0')}.${String(cc).padStart(2,'0')}`; };
const esc = t => t.replace(/[{}\\]/g, '');

// pack words into single lines by a character budget (keeps every caption ONE line)
function packByChars(ws, maxChars, maxWords){ const L=[]; let cur=[],len=0;
  for(const w of ws){ const add=(cur.length?1:0)+w.t.length;
    if(cur.length && (len+add>maxChars || cur.length>=maxWords)){ L.push(cur); cur=[]; len=0; }
    cur.push(w); len+=(cur.length>1?1:0)+w.t.length; }
  if(cur.length) L.push(cur); return L; }

const WHITE='&H00FFFFFF', BLACK='&H00000000', YELLOW='&H0000FFFF';
const ANCHOR='{\\an5\\pos(540,1360)}';

// pass 1: one "active word" state per word, in order
const states=[];
for(const line of packByChars(words, MAXCHARS, MAXWORDS)){
  for(let i=0;i<line.length;i++){
    const txt=line.map((w,j)=> j===i
      ? `{\\fscx122\\fscy122\\c${YELLOW}&}${esc(w.t)}{\\fscx100\\fscy100\\c${WHITE}&}`
      : esc(w.t)).join(' ');
    states.push({ a: line[i].a, text: ANCHOR+txt });
  }
}
// pass 2: end each state exactly when the next begins (no overlap, continuous)
const events=[];
for(let k=0;k<states.length;k++){
  const a=states[k].a, b=(k<states.length-1)? states[k+1].a : END;
  if(b>a) events.push(`Dialogue: 0,${cs(a)},${cs(b)},Cap,,0,0,0,,${states[k].text}`);
}

const ass = `[Script Info]
ScriptType: v4.00+
PlayResX: 1080
PlayResY: 1920
WrapStyle: 0
ScaledBorderAndShadow: yes

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Cap,${fontName},84,${WHITE},${WHITE},${BLACK},${BLACK},1,0,0,0,100,100,0,0,1,6,3,5,60,60,0,1

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
${events.join('\n')}
`;
process.stdout.write(ass);
