const assert=require('node:assert/strict');
const fs=require('node:fs');const path=require('node:path');
const {version,compare,packageFor}=require('../docs/assets/version.js');
assert.equal(compare('v0.1.10','0.1.9'),1);assert.equal(compare('0.1.4','0.1.4'),0);assert.equal(compare('0.1.4','0.2.0'),-1);assert.equal(compare('evil','0.1.4'),null);assert.equal(version('1.2.3-beta'),null);
const asset={name:'Open-Tangerine-0.1.4-macOS.zip',state:'uploaded',browser_download_url:'https://github.com/sintaxerrorpvtltd/Open-Tangerine/releases/download/v0.1.4/Open-Tangerine-0.1.4-macOS.zip'};
const release={tag_name:'v0.1.4',draft:false,prerelease:false,assets:[asset]};assert.equal(packageFor(release),asset);assert.equal(packageFor({...release,draft:true}),null);assert.equal(packageFor({...release,assets:[{...asset,browser_download_url:'https://example.com/evil.zip'}]}),null);
const docs=path.resolve(__dirname,'../docs');
for(const file of ['index.html','privacy.html','terms.html']){const html=fs.readFileSync(path.join(docs,file),'utf8');assert.match(html,/<html lang="en">/);for(const [,url] of html.matchAll(/(?:href|src)="([^"]+)"/g)){if(/^(https?:|mailto:|#)/.test(url))continue;const target=url.split('#')[0]||'./';assert.ok(fs.existsSync(path.resolve(docs,target)),`${file}: missing ${url}`);}}
console.log('PASS version comparison, download URL validation, prerelease/draft rejection and internal page links');
