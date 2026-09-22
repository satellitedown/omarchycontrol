// Canonical addresses are lowercase strings with exactly one 0x prefix.
// Invalid values remain unusable rather than becoming dispatcher operands.
function normalizeAddress(value) {
    if (typeof value !== "string")
        return "";
    var address = value.trim().replace(/^0x/i, "");
    return /^[0-9a-fA-F]+$/.test(address) ? "0x" + address.toLowerCase() : "";
}

// Lua decimal escapes must have three digits so following digits stay literal.
function luaQuote(value) {
    return '"' + String(value).replace(/[\x00-\x1f\x7f\\"]/g, function(character) {
        if (character === "\\" || character === '"')
            return "\\" + character;
        return "\\" + ("00" + character.charCodeAt(0)).slice(-3);
    }) + '"';
}

function finiteNumber(value) {
    return typeof value === "number" && isFinite(value);
}

// Hyprland gives named workspaces negative IDs; only special workspaces and
// absent/invalid IDs are excluded, not negative IDs with ordinary names.
function isNormalWorkspace(workspace) {
    if (!workspace || !finiteNumber(workspace.id)
            || Math.floor(workspace.id) !== workspace.id || workspace.id === 0)
        return false;
    var name = typeof workspace.name === "string" ? workspace.name : "";
    if (name === "special" || name.indexOf("special:") === 0)
        return false;
    return workspace.id > 0 || name.length > 0;
}

// Callers pass the complete workspace, never dispatch a negative numeric ID.
function workspaceSelector(workspace) {
    if (!isNormalWorkspace(workspace))
        return "";
    var name = typeof workspace.name === "string" ? workspace.name : "";
    if (workspace.id > 0 && (name.length === 0 || /^[0-9]+$/.test(name)))
        return String(workspace.id);
    return "name:" + name;
}

// Missing capture handles and missing geometry do not disqualify real clients.
// Pinned clients still belong to one monitor and must originate on a normal
// workspace; they are included once by the caller's address-keyed model.
function windowEligible(ipc, monitorId, workspaceId) {
    return !!ipc && ipc.mapped === true && ipc.hidden !== true
        && finiteNumber(monitorId) && ipc.monitor === monitorId
        && isNormalWorkspace(ipc.workspace)
        && (ipc.workspace.id === workspaceId || ipc.pinned === true);
}

function hasGeometry(ipc) {
    return !!ipc && !!ipc.at && !!ipc.size
        && finiteNumber(ipc.at[0]) && finiteNumber(ipc.at[1])
        && finiteNumber(ipc.size[0]) && finiteNumber(ipc.size[1])
        && ipc.size[0] > 0 && ipc.size[1] > 0
        && finiteNumber(ipc.at[0] + ipc.size[0] / 2)
        && finiteNumber(ipc.at[1] + ipc.size[1] / 2);
}

function miniatureRect(ipc, originX, originY, scaleX, scaleY) {
    if (!hasGeometry(ipc) || !finiteNumber(originX) || !finiteNumber(originY)
            || !finiteNumber(scaleX) || !finiteNumber(scaleY) || scaleX <= 0 || scaleY <= 0)
        return { x: 0, y: 0, width: 0, height: 0 };
    return { x: (ipc.at[0] - originX) * scaleX, y: (ipc.at[1] - originY) * scaleY,
        width: ipc.size[0] * scaleX, height: ipc.size[1] * scaleY };
}

// Sort IPC objects by center (y, x), then canonical address. Geometry-less
// clients have a stable place after geometric clients, rather than NaN keys.
function spatialCompare(a, b) {
    var aValid = hasGeometry(a);
    var bValid = hasGeometry(b);
    if (aValid !== bValid)
        return aValid ? -1 : 1;
    if (aValid) {
        var ay = a.at[1] + a.size[1] / 2;
        var by = b.at[1] + b.size[1] / 2;
        if (ay !== by)
            return ay < by ? -1 : 1;
        var ax = a.at[0] + a.size[0] / 2;
        var bx = b.at[0] + b.size[0] / 2;
        if (ax !== bx)
            return ax < bx ? -1 : 1;
    }
    var aa = normalizeAddress(a ? a.address : "");
    var ba = normalizeAddress(b ? b.address : "");
    return aa < ba ? -1 : aa > ba ? 1 : 0;
}

function extent(value) {
    return finiteNumber(value) && value > 0 ? value : 0;
}

// Split all intersecting free rectangles, then discard contained fragments.
// Rectangles may overlap each other, but never a placed window.
function subtractRect(free, used) {
    var next = [];
    for (var i = 0; i < free.length; ++i) {
        var r = free[i];
        var right = r.x + r.width, bottom = r.y + r.height;
        var usedRight = used.x + used.width, usedBottom = used.y + used.height;
        if (used.x >= right || usedRight <= r.x || used.y >= bottom || usedBottom <= r.y) {
            next.push(r);
            continue;
        }
        if (used.x > r.x) next.push({ x: r.x, y: r.y, width: used.x - r.x, height: r.height });
        if (usedRight < right) next.push({ x: usedRight, y: r.y, width: right - usedRight, height: r.height });
        if (used.y > r.y) next.push({ x: r.x, y: r.y, width: r.width, height: used.y - r.y });
        if (usedBottom < bottom) next.push({ x: r.x, y: usedBottom, width: r.width, height: bottom - usedBottom });
    }
    for (var a = next.length - 1; a >= 0; --a) {
        for (var b = 0; b < next.length; ++b) {
            if (a === b) continue;
            var x = next[a], y = next[b];
            if (x.x >= y.x && x.y >= y.y && x.x + x.width <= y.x + y.width
                    && x.y + x.height <= y.y + y.height) {
                next.splice(a, 1);
                break;
            }
        }
    }
    return next;
}

function packWindows(sizes, order, W, H, scale, gap, chrome) {
    var free = [{ x: 0, y: 0, width: W + gap, height: H + gap }];
    var result = new Array(sizes.length);
    for (var i = 0; i < order.length; ++i) {
        var index = order[i], size = sizes[index];
        var width = size.width * scale + 12 * chrome + gap;
        var height = size.height * scale + 38 * chrome + gap;
        var best = -1, shortSide = Infinity, longSide = Infinity;
        for (var j = 0; j < free.length; ++j) {
            var dx = free[j].width - width, dy = free[j].height - height;
            if (dx < 0 || dy < 0) continue;
            var small = Math.min(dx, dy), large = Math.max(dx, dy);
            if (small < shortSide || (small === shortSide && large < longSide)) {
                best = j; shortSide = small; longSide = large;
            }
        }
        if (best < 0) return null;
        var placed = { x: free[best].x, y: free[best].y, width: width, height: height };
        result[index] = { x: placed.x, y: placed.y, width: width - gap,
            height: height - gap, chromeScale: chrome };
        free = subtractRect(free, placed);
    }
    return result;
}

// Use the windows' real proportions and relative sizes, not equal grid cells.
// Try complementary packing orders and maximize a common preview scale.
function windowLayout(windows, W, H, monitor) {
    W = extent(W); H = extent(H);
    if (!windows.length || !W || !H) return [];
    var sizes = [], order = [];
    var chrome = Math.min(1, W / (windows.length * 24), H / 76);
    var gap = 24 * chrome;
    var upper = Infinity;
    for (var i = 0; i < windows.length; ++i) {
        var size = windows[i].size;
        var valid = size && extent(size[0]) && extent(size[1]);
        var w = valid ? size[0] : 800, h = valid ? size[1] : 600;
        sizes.push({ width: w, height: h });
        order.push(i);
        upper = Math.min(upper, (W - 12 * chrome) / w, (H - 38 * chrome) / h);
    }
    var best = null, bestScale = -1;
    for (var mode = 0; mode < 3; ++mode) {
        order.sort(function(a, b) {
            var sa = sizes[a], sb = sizes[b];
            return (mode === 0 ? sb.width * sb.height - sa.width * sa.height
                : mode === 1 ? sb.width - sa.width : sb.height - sa.height) || a - b;
        });
        var low = 0, high = upper;
        var candidate = packWindows(sizes, order, W, H, 0, gap, chrome);
        for (var iteration = 0; iteration < 18; ++iteration) {
            var scale = (low + high) / 2;
            var packed = packWindows(sizes, order, W, H, scale, gap, chrome);
            if (packed) { low = scale; candidate = packed; }
            else high = scale;
        }
        if (candidate && low > bestScale) { best = candidate; bestScale = low; }
    }
    if (!best) return [];
    // Center the group, then let each window settle toward its desktop position
    // within collision-free intervals. This avoids rigid aligned rows.
    var right = 0, bottom = 0;
    for (var k = 0; k < best.length; ++k) {
        right = Math.max(right, best[k].x + best[k].width);
        bottom = Math.max(bottom, best[k].y + best[k].height);
    }
    for (var k = 0; k < best.length; ++k) {
        best[k].x += (W - right) / 2;
        best[k].y += (H - bottom) / 2;
    }
    if (monitor && extent(monitor.width) && extent(monitor.height)) {
        // The packing itself has no preferred corner. Choose its orientation
        // nearest the desktop arrangement before settling individual windows.
        var orientation = 0, distance = Infinity;
        for (var flip = 0; flip < 4; ++flip) {
            var cost = 0;
            for (var k = 0; k < best.length; ++k) {
                if (!hasGeometry(windows[k])) continue;
                var cx = best[k].x + best[k].width / 2;
                var cy = best[k].y + best[k].height / 2;
                var tx = (windows[k].at[0] + windows[k].size[0] / 2 - monitor.x) / monitor.width * W;
                var ty = (windows[k].at[1] + windows[k].size[1] / 2 - monitor.y) / monitor.height * H;
                var dx = ((flip & 1) ? W - cx : cx) - tx;
                var dy = ((flip & 2) ? H - cy : cy) - ty;
                cost += dx * dx + dy * dy;
            }
            if (cost < distance) { distance = cost; orientation = flip; }
        }
        for (var k = 0; k < best.length; ++k) {
            if (orientation & 1) best[k].x = W - best[k].x - best[k].width;
            if (orientation & 2) best[k].y = H - best[k].y - best[k].height;
        }
        for (var pass = 0; pass < 3; ++pass) {
            for (var k = 0; k < best.length; ++k) {
                var source = windows[k];
                if (!hasGeometry(source)) continue;
                var card = best[k];
                for (var axis = 0; axis < 2; ++axis) {
                    var p = axis === 0 ? "x" : "y", q = axis === 0 ? "y" : "x";
                    var length = axis === 0 ? "width" : "height";
                    var cross = axis === 0 ? "height" : "width";
                    var limit = axis === 0 ? W : H;
                    var target = (source.at[axis] + source.size[axis] / 2 - monitor[p])
                        / monitor[length] * limit - card[length] / 2;
                    var min = 0, max = limit - card[length];
                    for (var j = 0; j < best.length; ++j) {
                        if (j === k) continue;
                        var other = best[j];
                        if (card[q] + card[cross] + gap <= other[q] + 0.001
                                || other[q] + other[cross] + gap <= card[q] + 0.001) continue;
                        if (other[p] < card[p]) min = Math.max(min, other[p] + other[length] + gap);
                        else max = Math.min(max, other[p] - card[length] - gap);
                    }
                    if (min <= max) card[p] = Math.max(min, Math.min(max, target));
                }
            }
        }
    }
    return best;
}

// Arrow navigation follows visible geometry now that rows/columns do not exist.
function neighbor(rects, index, dx, dy) {
    if (index < 0 || index >= rects.length) return -1;
    var source = rects[index], best = -1, score = Infinity;
    for (var i = 0; i < rects.length; ++i) {
        if (i === index) continue;
        var candidate = rects[i];
        var x = candidate.x + candidate.width / 2 - source.x - source.width / 2;
        var y = candidate.y + candidate.height / 2 - source.y - source.height / 2;
        var forward = x * dx + y * dy;
        if (forward <= 1) continue;
        var sideways = Math.abs(x * dy - y * dx);
        var value = forward + 2 * sideways;
        if (value < score) { score = value; best = i; }
    }
    return best;
}
