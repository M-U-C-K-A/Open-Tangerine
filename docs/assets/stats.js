'use strict';
(async () => {
  const api = 'https://api.github.com/repos/sintaxerrorpvtltd/Open-Tangerine';
  async function get(path) {
    const response = await fetch(api + path, {signal: AbortSignal.timeout(10000), headers:{Accept:'application/vnd.github+json'}});
    if (!response.ok) throw new Error('GitHub unavailable or rate limited');
    return response.json();
  }
  try {
    const [repo, first] = await Promise.all([get(''), get('/releases?per_page=100&page=1')]);
    let releases = first, page = 1, batch = first;
    while (batch.length === 100) {
      batch = await get(`/releases?per_page=100&page=${++page}`);
      releases = releases.concat(batch);
    }
    let total = 0;
    for (const release of releases) {
      const count = release.assets.filter(a => /^Open-Tangerine-.*-macOS\.zip$/.test(a.name)).reduce((sum,a) => sum + a.download_count, 0);
      total += count;
      const row = document.createElement('tr');
      for (const value of [release.tag_name, count]) {
        const cell = document.createElement('td'); cell.textContent = value; row.append(cell);
      }
      document.getElementById('download-rows').append(row);
    }
    document.getElementById('download-total').textContent = `${total} release ZIP download requests`;
    document.getElementById('repo-counts').textContent = `${repo.stargazers_count} stars · ${repo.forks_count} forks · ${repo.open_issues_count} open issues and pull requests combined`;
    document.getElementById('stats-status').textContent = `Checked ${new Date().toLocaleString()}. Refresh this page to check again.`;
  } catch {
    document.getElementById('stats-status').textContent = 'GitHub could not be reached or its public API limit was reached. Try again later; no counts have been guessed.';
    document.getElementById('repo-counts').textContent = 'Counts unavailable.';
  }
})();
