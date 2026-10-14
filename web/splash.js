// Removes the plain HTML splash on Flutter's first frame. A file, not inline, so the server's strict CSP allows it.
window.addEventListener("flutter-first-frame", function () {
  var s = document.getElementById("splash");
  if (s) s.remove();
});
