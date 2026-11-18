(function(view) {
  try {
    Uint8Array.prototype.slice.call(view, 0, 0);
    const proto = Object.getPrototypeOf(Uint8Array.prototype);
    const get = key => Object.getOwnPropertyDescriptor(proto, key).get.call(view);
    if (get(Symbol.toStringTag) !== 'Uint8Array') return -1;
    const buffer = get('buffer');
    Object.getOwnPropertyDescriptor(ArrayBuffer.prototype, 'byteLength').get.call(buffer);
    const resizable = Object.getOwnPropertyDescriptor(ArrayBuffer.prototype, 'resizable');
    if (resizable && resizable.get.call(buffer)) return -1;
    return get('byteLength');
  } catch (_) { return -1; }
})
