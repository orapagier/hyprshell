.pragma library

function mediaWindow(windows, media) {
    function key(value) { return String(value || '').toLowerCase().replace(/\.desktop$/, ''); }
    let app = key(media.appId), name = key(media.appName);
    let candidates = windows.filter(t => {
        let info = t.lastIpcObject || {};
        if (media.processId && Number(info.pid) === Number(media.processId)) return true;
        let cls = key(info.class || t.wayland?.appId);
        return cls && ((app && cls === app) || (name && cls === name));
    });
    let title = key(media.trackTitle);
    let titled = title ? candidates.filter(t => key(t.title).includes(title)) : [];
    return titled.length === 1 ? titled[0] : candidates.length === 1 ? candidates[0] : null;
}
