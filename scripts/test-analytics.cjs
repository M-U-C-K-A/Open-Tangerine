const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const deployedSource = fs.readFileSync('docs/assets/analytics.js', 'utf8');
assert.match(deployedSource, /const projectToken = "";/, 'Collection remains disabled without an isolated project');
const source = deployedSource.replace('const projectToken = "";', 'const projectToken = "test-only";');
function run({saved, signal = false, hostname = 'sintaxerrorpvtltd.github.io', blocked = false} = {}) {
  const sent = [], elements = [], handlers = {};
  let stored = saved ? JSON.stringify(saved) : null;
  const location = new URL(`https://${hostname}/Open-Tangerine/?version=0.1.7&secret=private&utm_source=reddit`);
  const document = {
    referrer: 'https://www.reddit.com/private/path?secret=private',
    createElement() { const element = {setAttribute(){}, addEventListener(k, fn){this[k] = fn;}, querySelector(){return {focus(){}};}}; elements.push(element); return element; },
    body: {append(){}}, querySelector(){return {append(){}};},
    addEventListener(k, fn){handlers[k] = fn;}
  };
  vm.runInNewContext(source, {location, document, navigator: {globalPrivacyControl: signal}, crypto: {randomUUID: () => 'test-id'}, URL, URLSearchParams, Date, JSON,
    localStorage: {getItem(){if(blocked) throw Error(); return stored;}, setItem(k,v){if(blocked) throw Error(); stored=v;}},
    fetch(url, options){sent.push({url, options, payload: JSON.parse(options.body)});return Promise.resolve({ok:true});}
  });
  return {sent, elements, stored:()=>JSON.parse(stored), choose(choice){elements[0].click({target:{closest:()=>({dataset:{choice}})}});}, click(href){handlers.click({target:{closest:()=>({href})}});}};
}
let test = run();
assert.equal(test.sent.length, 0, 'No requests before consent');
test.choose('deny'); assert.equal(test.sent.length, 0);
test.choose('allow'); assert.equal(test.sent.length, 1);
const page = test.sent[0].payload;
assert.equal(page.event, '$pageview');
assert.equal(page.properties.app, 'open-tangerine');
assert.equal(page.properties.utm_source, 'reddit');
assert.equal(page.properties.$referring_domain, 'www.reddit.com');
assert(!JSON.stringify(page).includes('private'), 'Strip query strings and referrer paths');
test.click('https://github.com/sintaxerrorpvtltd/Open-Tangerine/releases/download/v0.1.7/Open-Tangerine-0.1.7-macOS.zip');
assert.equal(test.sent[1].payload.event, 'ot_download_click');
assert.equal(test.sent[1].payload.properties.release, 'v0.1.7');
test.click('https://github.com/sintaxerrorpvtltd/Open-Tangerine/releases');
assert.equal(test.sent[2].payload.event, 'ot_releases_click', 'Fallback is not a download');
test.choose('deny');
test.click('https://github.com/sintaxerrorpvtltd/Open-Tangerine');
assert.equal(test.sent.length, 3, 'Withdrawal stops future events');
assert.equal(test.stored().id, null, 'Withdrawal removes identifier');
const saved = {choice:'allow', id:'returning-id', expires:Date.now()+100000};
assert.equal(run({saved}).sent[0].payload.distinct_id, 'returning-id');
assert.equal(run({saved, signal:true}).sent.length, 0, 'GPC overrides previous consent');
assert.equal(run({saved:{...saved, expires:0}}).sent.length, 0, 'Expired permission is not reused');
assert.equal(run({hostname:'localhost'}).sent.length, 0, 'Local previews never count');
test = run({blocked:true}); test.choose('allow'); assert.equal(test.sent.length, 1, 'Blocked storage does not break the page');
console.log('Analytics consent, privacy, attribution, download and withdrawal checks passed.');
(async () => {
  const nodes = new Map();
  const element = () => ({children:[], append(child){this.children.push(child);}});
  const document = {createElement:element, getElementById(id){if(!nodes.has(id)) nodes.set(id,element());return nodes.get(id);}};
  const release = {tag_name:'v1',assets:[{name:'Open-Tangerine-1-macOS.zip',download_count:2},{name:'SHA256SUMS.txt',download_count:99}]};
  await vm.runInNewContext(fs.readFileSync('docs/assets/stats.js','utf8'), {document, Date, AbortSignal,
    fetch:async url => ({ok:true, json:async () => url.includes('&page=1') ? Array(100).fill(release) : url.includes('&page=2') ? [release] : {stargazers_count:3,forks_count:4,open_issues_count:5}})
  });
  assert.equal(nodes.get('download-total').textContent,'202 release ZIP download requests');
  assert.equal(nodes.get('download-rows').children.length,101,'All release pages counted');
  assert.match(nodes.get('repo-counts').textContent,/3 stars · 4 forks/);
  console.log('Public activity counts include pagination and exclude checksum downloads.');
})().catch(error => { console.error(error); process.exitCode=1; });
