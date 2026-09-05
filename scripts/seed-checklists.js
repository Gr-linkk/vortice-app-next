#!/usr/bin/env node
// Seed checklist templates + items into Supabase from JSON files
// Uses service role key to bypass RLS

const fs = require('fs');
const path = require('path');
const https = require('https');

const EXPECTED_PROJECT_HOST = 'hkjpojobdbbtjkhaudki.supabase.co';
const REPO_ROOT = path.resolve(__dirname, '..');
const SUPABASE_URL = process.env.SUPABASE_URL;
const SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const OWNER_ID = process.env.VORTICE_SEED_OWNER_ID;
const MOTOR_YACHT_TYPE_ID = '00000000-0000-0000-0000-000000000001';

const CHECKLIST_DIR = path.resolve(
  process.env.VORTICE_CHECKLIST_DIR || path.join(REPO_ROOT, 'seed', 'checklists'),
);

if (process.argv[2] !== '--confirm-vortice-next') {
  console.error('Refusing to seed without --confirm-vortice-next.');
  process.exit(1);
}

if (!SUPABASE_URL || !SERVICE_KEY || !OWNER_ID) {
  console.error(
    'Missing SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, or VORTICE_SEED_OWNER_ID.',
  );
  process.exit(1);
}

let configuredHost;
try {
  configuredHost = new URL(SUPABASE_URL).host;
} catch {
  console.error('SUPABASE_URL is not a valid URL.');
  process.exit(1);
}

if (configuredHost !== EXPECTED_PROJECT_HOST) {
  console.error(`Refusing to seed unexpected Supabase host: ${configuredHost}`);
  process.exit(1);
}

if (!CHECKLIST_DIR.startsWith(`${REPO_ROOT}${path.sep}`)) {
  console.error('VORTICE_CHECKLIST_DIR must resolve inside this repository.');
  process.exit(1);
}

if (!fs.existsSync(CHECKLIST_DIR)) {
  console.error(`Checklist fixture directory does not exist: ${CHECKLIST_DIR}`);
  process.exit(1);
}

function supabaseRequest(method, tablePath, body) {
  return new Promise((resolve, reject) => {
    const url = new URL(`${SUPABASE_URL}/rest/v1/${tablePath}`);
    const options = {
      method,
      hostname: url.hostname,
      path: url.pathname + url.search,
      headers: {
        'Content-Type': 'application/json',
        'apikey': SERVICE_KEY,
        'Authorization': `Bearer ${SERVICE_KEY}`,
        'Prefer': 'return=representation',
      },
    };
    const req = https.request(options, (res) => {
      let data = '';
      res.on('data', (chunk) => data += chunk);
      res.on('end', () => {
        if (res.statusCode >= 400) {
          reject(new Error(`${res.statusCode}: ${data}`));
        } else {
          resolve(data ? JSON.parse(data) : null);
        }
      });
    });
    req.on('error', reject);
    if (body) req.write(JSON.stringify(body));
    req.end();
  });
}

// First ensure asset_types has our placeholder
async function ensureAssetTypes() {
  console.log('Ensuring asset_types exist...');
  const types = [
    { id: '00000000-0000-0000-0000-000000000001', category: 'Marine Vessels', name: 'Motor Yacht', tracking_unit: 'engine_hours' },
    { id: '00000000-0000-0000-0000-000000000002', category: 'Marine Vessels', name: 'Sailing Yacht', tracking_unit: 'engine_hours' },
    { id: '00000000-0000-0000-0000-000000000003', category: 'Marine Vessels', name: 'Catamaran', tracking_unit: 'engine_hours' },
    { id: '00000000-0000-0000-0000-000000000004', category: 'Marine Vessels', name: 'Sport Fisher', tracking_unit: 'engine_hours' },
    { id: '00000000-0000-0000-0000-000000000005', category: 'Marine Vessels', name: 'Panga / Work Boat', tracking_unit: 'engine_hours' },
    { id: '00000000-0000-0000-0000-000000000006', category: 'Marine Vessels', name: 'Center Console', tracking_unit: 'engine_hours' },
    { id: '00000000-0000-0000-0000-000000000007', category: 'Dredging Equipment', name: 'Hydraulic Dredge', tracking_unit: 'engine_hours' },
    { id: '00000000-0000-0000-0000-000000000008', category: 'Dredging Equipment', name: 'Cutter Suction Dredge', tracking_unit: 'engine_hours' },
    { id: '00000000-0000-0000-0000-000000000009', category: 'Heavy Equipment', name: 'Excavator', tracking_unit: 'engine_hours' },
    { id: '00000000-0000-0000-0000-00000000000a', category: 'Heavy Equipment', name: 'Wheel Loader', tracking_unit: 'engine_hours' },
    { id: '00000000-0000-0000-0000-00000000000b', category: 'Heavy Equipment', name: 'Bulldozer', tracking_unit: 'engine_hours' },
    { id: '00000000-0000-0000-0000-00000000000c', category: 'Power Generation', name: 'Diesel Genset', tracking_unit: 'engine_hours' },
    { id: '00000000-0000-0000-0000-00000000000d', category: 'Other', name: 'Custom / Other', tracking_unit: 'engine_hours' },
  ];

  for (const t of types) {
    try {
      await supabaseRequest('POST', 'asset_types', t);
      console.log(`  ✅ ${t.name}`);
    } catch (e) {
      if (e.message.includes('409') || e.message.includes('duplicate') || e.message.includes('23505')) {
        console.log(`  ⏭️  ${t.name} (already exists)`);
      } else {
        console.log(`  ❌ ${t.name}: ${e.message}`);
      }
    }
  }
}

async function seedChecklists() {
  const files = fs.readdirSync(CHECKLIST_DIR).filter(f => f.endsWith('.json')).sort();
  console.log(`\nFound ${files.length} checklist files\n`);

  for (const file of files) {
    const raw = JSON.parse(fs.readFileSync(path.join(CHECKLIST_DIR, file), 'utf8'));
    const isBoat = file.startsWith('boat-');
    const isDredge = file.startsWith('dredge-');

    // Determine asset type
    const assetTypeId = isDredge ? '00000000-0000-0000-0000-000000000007' : MOTOR_YACHT_TYPE_ID;

    // Parse interval from filename
    const match = file.match(/(\d+)hr/i);
    const intervalHours = match ? parseInt(match[1]) : null;
    const isHaulout = file.includes('haulout');

    // Build template
    const template = {
      asset_type_id: assetTypeId,
      checklist_type: 'pm',
      interval_hours: intervalHours,
      interval_label: isHaulout ? 'Haulout' : (intervalHours ? `${intervalHours}HR` : raw.title),
      name: raw.title,
      description: `${isBoat ? 'Marine' : 'Dredge'} PM checklist — ${isHaulout ? 'Haulout' : intervalHours + 'HR'} service interval`,
      version: 1,
      is_active: true,
      created_by: OWNER_ID,
    };

    try {
      const [inserted] = await supabaseRequest('POST', 'checklist_templates', template);
      const templateId = inserted.id;
      console.log(`✅ Template: ${raw.title} (${templateId})`);

      // Build items from sections
      const items = [];
      let sortOrder = 0;
      for (const section of (raw.sections || [])) {
        for (const item of (section.items || [])) {
          items.push({
            template_id: templateId,
            sort_order: sortOrder++,
            description_en: item,
            description_es: null,
            category: section.name,
            requires_photo: false,
          });
        }
      }

      // Insert in batches of 50
      for (let i = 0; i < items.length; i += 50) {
        const batch = items.slice(i, i + 50);
        await supabaseRequest('POST', 'checklist_items', batch);
      }
      console.log(`   📋 ${items.length} items inserted`);

    } catch (e) {
      console.log(`❌ ${raw.title}: ${e.message}`);
    }
  }
}

// Also seed an operator daily checklist
async function seedOperatorChecklist() {
  console.log('\nSeeding operator daily checklist...');

  const template = {
    asset_type_id: MOTOR_YACHT_TYPE_ID,
    checklist_type: 'operator_daily',
    name: 'Daily Pre-Departure Checklist',
    description: 'Standard pre-departure checklist for vessel operators',
    version: 1,
    is_active: true,
    created_by: OWNER_ID,
  };

  try {
    const [inserted] = await supabaseRequest('POST', 'checklist_templates', template);
    console.log(`✅ Template: ${template.name} (${inserted.id})`);

    const items = [
      'Visual hull inspection — no damage, lines clear',
      'Bilge check — dry, no oil sheen',
      'Engine oil level check',
      'Coolant level check',
      'Fuel level — sufficient for planned trip',
      'Battery voltage check — all banks',
      'Navigation lights — all operational',
      'VHF radio — powered on, weather check',
      'Fire extinguishers — accessible, gauge green',
      'Safety equipment — PFDs, throwable, flares',
      'Steering — responsive, full range of motion',
      'Engine start — smooth start, normal idle',
      'Gauges — oil pressure, temp, voltage all normal',
      'Raw water flow — confirmed at exhaust',
      'Bilge pump test — auto and manual',
      'Horn test',
      'Anchor/windlass check',
      'Deck clear — hatches, cleats, fenders',
      'Passengers briefed on safety',
      'Weather conditions acceptable for departure',
    ].map((q, i) => ({
      template_id: inserted.id,
      sort_order: i,
      description_en: q,
      description_es: null,
      category: i < 5 ? 'Pre-Start' : i < 12 ? 'Safety & Systems' : i < 16 ? 'Engine Start' : 'Final Checks',
      requires_photo: false,
    }));

    await supabaseRequest('POST', 'checklist_items', items);
    console.log(`   📋 ${items.length} items inserted`);

  } catch (e) {
    console.log(`❌ ${template.name}: ${e.message}`);
  }

  // Post-trip checklist
  const postTrip = {
    asset_type_id: MOTOR_YACHT_TYPE_ID,
    checklist_type: 'operator_daily',
    name: 'Post-Trip Checklist',
    description: 'Standard post-trip checklist for vessel operators',
    version: 1,
    is_active: true,
    created_by: OWNER_ID,
  };

  try {
    const [inserted] = await supabaseRequest('POST', 'checklist_templates', postTrip);
    console.log(`✅ Template: ${postTrip.name} (${inserted.id})`);

    const items = [
      'Record trip hours',
      'Record fuel added',
      'Engine shutdown — normal cooldown',
      'Bilge check — no new water or oil',
      'Clean deck and cockpit',
      'Secure all hatches and ports',
      'Shore power connected (if at dock)',
      'Lines and fenders secure',
      'Navigation electronics powered down',
      'Report any issues noticed during trip',
    ].map((q, i) => ({
      template_id: inserted.id,
      sort_order: i,
      description_en: q,
      description_es: null,
      category: i < 2 ? 'Logging' : i < 4 ? 'Engine & Systems' : 'Securing',
      requires_photo: false,
    }));

    await supabaseRequest('POST', 'checklist_items', items);
    console.log(`   📋 ${items.length} items inserted`);

  } catch (e) {
    console.log(`❌ ${postTrip.name}: ${e.message}`);
  }
}

async function main() {
  console.log('🔧 Vórtice — Seeding Supabase\n');
  await ensureAssetTypes();
  await seedChecklists();
  await seedOperatorChecklist();
  console.log('\n✅ Done!');
}

main().catch(console.error);
