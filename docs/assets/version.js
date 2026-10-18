(function(root){
  function version(text){if(typeof text!=='string'||!/^v?\d{1,9}\.\d{1,9}\.\d{1,9}$/.test(text))return null;return text.replace(/^v/,'').split('.').map(Number);}
  function compare(a,b){a=version(a);b=version(b);if(!a||!b)return null;for(let i=0;i<3;i++){if(a[i]!==b[i])return a[i]>b[i]?1:-1;}return 0;}
  function packageFor(release){if(!release||release.draft||release.prerelease||!version(release.tag_name))return null;const tag=release.tag_name;const name=`Open-Tangerine-${tag.replace(/^v/,'')}-macOS.zip`;return (release.assets||[]).find(a=>a.name===name&&a.browser_download_url===`https://github.com/sintaxerrorpvtltd/Open-Tangerine/releases/download/${tag}/${name}`&&a.state==='uploaded')||null;}
  const api={version,compare,packageFor};if(typeof module!=='undefined')module.exports=api;else root.TangerineVersion=api;
})(typeof window!=='undefined'?window:this);
