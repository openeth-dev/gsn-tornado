if (window.location.search) {
  console.log('redirect')
  window.location = window.location.origin + window.location.pathname
}
