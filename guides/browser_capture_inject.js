// This is a hook that can be added to browser console that logs all requests made
// Even ones that traditionally get blocked by browser protection rules

// Note that logins that occur in iframes still won't be logged
// The hooks also need to be run in a console on the iframes
// Go to dev tools -> sources -> click on the right iframe and enter this in the iframe console
// You can test the hook by typing in a wrong username/password and should see the hook invoked

(() => {
  const log = (...args) => console.log("[hook]", ...args);

  // hook fetch
  const originalFetch = window.fetch;
  window.fetch = async function (input, init) {
    const url = input instanceof Request ? input.url : input;
    const method = (init && init.method) || (input instanceof Request ? input.method : "GET");
    log("fetch", method, url);

    if (input instanceof Request) {
      const clone = input.clone();
      const body = await clone.text();
      if (body) log("fetch body", body);
    } else if (init && init.body) {
      log("fetch body", init.body);
    }
    return originalFetch.call(this, input, init);
  };

  // hook XHR
  const origOpen = XMLHttpRequest.prototype.open;
  const origSend = XMLHttpRequest.prototype.send;
  XMLHttpRequest.prototype.open = function (method, url, ...rest) {
    this.__requestMethod = method;
    this.__requestUrl = url;
    return origOpen.call(this, method, url, ...rest);
  };
  XMLHttpRequest.prototype.send = function (body) {
    log("xhr", this.__requestMethod, this.__requestUrl);
    if (body) log("xhr body", body);
    return origSend.call(this, body);
  };

  // hook standard form submit
  const origSubmit = HTMLFormElement.prototype.submit;
  HTMLFormElement.prototype.submit = function () {
    log("form submit", this.action || document.location.href, this.method || "GET");
    const formData = new FormData(this);
    for (const [key, value] of formData.entries()) {
      log(`form field`, key, value);
    }
    return origSubmit.call(this);
  };
  document.addEventListener("submit", (evt) => {
    const form = evt.target;
    log("form submit event", form.action, form.method);
  }, true);

  log("hooks installed");
})();
