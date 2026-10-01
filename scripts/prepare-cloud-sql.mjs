import { readdir, readFile, writeFile } from 'node:fs/promises';
const files=(await readdir('supabase/migrations')).filter(f=>f.endsWith('.sql')).sort();
await writeFile('supabase/development-setup.sql', '-- DEVELOPMENT ONLY. Run once in a new empty DEV project. No real personal data.\n'+(await Promise.all(files.map(f=>readFile(`supabase/migrations/${f}`,'utf8')))).join('\n')+'\n'+await readFile('supabase/seed.sql','utf8'));
console.log('Generated supabase/development-setup.sql from versioned migrations and fictional seed.');
