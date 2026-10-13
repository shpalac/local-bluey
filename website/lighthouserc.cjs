module.exports = {
  ci: {
    collect: {
      startServerCommand: 'npm run preview -- --host 127.0.0.1',
      startServerReadyPattern: 'Local',
      url: ['http://127.0.0.1:4321/local-bluey/'],
      numberOfRuns: 1,
      settings: { chromeFlags: '--no-sandbox --disable-dev-shm-usage' }
    },
    assert: {
      assertions: {
        'categories:accessibility': ['error', { minScore: 0.85 }],
        'categories:best-practices': ['warn', { minScore: 0.8 }],
        'categories:performance': ['warn', { minScore: 0.65 }],
        'categories:seo': ['warn', { minScore: 0.85 }]
      }
    },
    upload: { target: 'filesystem', outputDir: '.lighthouseci' }
  }
};
// Site-only audit: no production credentials or analytics.
