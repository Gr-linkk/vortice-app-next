{{flutter_js}}
{{flutter_build_config}}
(async () => {
  if ('serviceWorker' in navigator && window.isSecureContext) {
    try {
      const registration = await navigator.serviceWorker.register('workspace-worker.js');
      // `ready` never rejects if installation fails (for example, a cache quota
      // error). Observe installation failure so connected use can still start.
      if (!registration.active && registration.installing) {
        const worker = registration.installing;
        await new Promise((resolve, reject) => {
          const changed = () => {
            if (worker.state === 'activated') resolve();
            if (worker.state === 'redundant') reject(new Error('Offline shell installation failed'));
          };
          worker.addEventListener('statechange', changed);
          changed();
        });
      }
    } catch (error) {
      console.warn('The offline app shell could not be prepared.', error);
    }
  }
  _flutter.loader.load();
})();
