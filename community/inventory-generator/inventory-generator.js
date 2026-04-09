/*
 * SPDX-FileCopyrightText: 2026 Pauline Legrand <pauline.legrand@numerique.gouv.fr>
 * SPDX-License-Identifier: MIT
 */

const state = { user: {}, machine: {} };
const tagState = {};
const advState = {};
const advGroupState = {};

let securixOptions = [];
let currentFilename = '';
let currentContent = '';


const FIXED_USER_FIELDS = [
  {
    section: 'Identité',
    fields: [
      {
        id: 'securix.self.user.username',
        label: 'username',
        type: 'str',
        required: true,
        placeholder: 'dtintin',
        onInput: function (v) {
          document.getElementById('u-filename-preview').textContent = v || 'username';
        }
      },
      {
        id: 'securix.self.user.email',
        label: 'email',
        type: 'email',
        placeholder: 'dupont.tintin@email.fr'
      }
    ]
  }
];

const FIXED_MACHINE_FIELDS = [
  {
    section: 'Matériel',
    fields: [
      {
        id: 'securix.self.machine.serialNumber',
        label: 'Numéro de série',
        type: 'str',
        required: true,
        placeholder: 'PF63VYZ9',
        uppercase: true,
        onInput: function (v) {
          document.getElementById('m-filename-preview').textContent = v.toUpperCase() || 'SN';
        }
      }
    ]
  }
];


function el(tag, attrs, ...children) {
  attrs = attrs || {};
  const e = document.createElement(tag);

  for (const [k, v] of Object.entries(attrs)) {
    if (k === 'class') {
      e.className = v;
    } else if (k.startsWith('on')) {
      e.addEventListener(k.slice(2), v);
    } else {
      e.setAttribute(k, v);
    }
  }

  for (const c of children) {
    if (typeof c === 'string') {
      e.appendChild(document.createTextNode(c));
    } else if (c) {
      e.appendChild(c);
    }
  }

  return e;
}


function renderInputFor(opt, stateTarget, stateKey) {
  const type = opt.type || { kind: 'str' };
  const key = stateKey || opt.id || opt.path;

  if (type.kind === 'bool') {
    const init = stateTarget
      ? (stateTarget[key] != null ? stateTarget[key] : (opt.default != null ? opt.default : false))
      : (opt.default != null ? opt.default : false);

    const row = el('div', { class: 'toggle-row' + (init ? ' active' : '') });
    const tog = el('div', { class: 'toggle' + (init ? ' on' : '') });
    const valEl = el('div', { class: 'toggle-value' }, String(init));

    if (stateTarget) {
      stateTarget[key] = init;
    }

    row.onclick = function () {
      const v = !row.classList.contains('active');
      row.classList.toggle('active', v);
      tog.classList.toggle('on', v);
      valEl.textContent = String(v);
      if (stateTarget) {
        stateTarget[key] = v;
      }
    };

    row.append(tog, el('div', { class: 'toggle-label' }, key), valEl);
    return row;

  } else if (type.kind === 'enum') {
    const sel = el('select');

    if (!opt.required) {
      sel.appendChild(el('option', { value: '' }, '— non spécifié'));
    }

    for (const v of (type.values || [])) {
      const o = el('option', { value: v }, v);
      if (v === opt.default) {
        o.selected = true;
      }
      sel.appendChild(o);
    }

    if (stateTarget) {
      stateTarget[key] = sel.value;
    }

    sel.onchange = function () {
      if (stateTarget) {
        stateTarget[key] = sel.value;
      }
    };

    return sel;

  } else if (type.kind === 'list') {
    const wrapId = 'wrap-' + key;
    tagState[wrapId] = (stateTarget && stateTarget[key]) || [];

    if (stateTarget) {
      stateTarget[key] = tagState[wrapId];
    }

    const hintText = opt.placeholder ||
      (opt.example
        ? 'ex: ' + (Array.isArray(opt.example) ? opt.example[0] : opt.example)
        : 'Entrée pour valider');

    const wrap = el('div', { class: 'tag-input-wrap', id: wrapId });
    wrap.appendChild(el('div', { class: 'tag-hint' }, hintText));

    const inp = el('input', {
      type: 'text',
      placeholder: 'Entrée pour valider',
      style: 'font-size:14px;margin-top:4px;'
    });

    let isPasting = false;

    inp.addEventListener('paste', function (e) {
      e.preventDefault();
      isPasting = true;

      const raw = (e.clipboardData || window.clipboardData).getData('text');
      const parts = raw.split(/[\n\r,]+/).map(function (s) { return s.trim(); }).filter(Boolean);

      if (parts.length === 0) {
        isPasting = false;
        return;
      }

      if (parts.length === 1) {
        inp.value = parts[0];
        isPasting = false;
        return;
      }

      for (const part of parts) {
        addTag(wrapId, part);
      }
      inp.value = '';
      isPasting = false;
    });

    inp.onkeydown = function (e) {
      if (isPasting) {
        return;
      }
      if (e.key === 'Enter' || e.key === ',') {
        e.preventDefault();
        const v = inp.value.trim().replace(/,$/, '');
        if (v) {
          addTag(wrapId, v, inp);
        }
      } else if (e.key === 'Backspace' && !inp.value && tagState[wrapId].length) {
        removeTag(wrapId, tagState[wrapId].length - 1);
      }
    };

    if (key.includes('u2f')) {
      inp.oninput = function () {
        const v = inp.value.trim();
        if (v.endsWith('+presence+pin') || v.endsWith('+presence') || v.endsWith('+pin')) {
          addTag(wrapId, v, inp);
        }
      };
    }

    wrap.onclick = function () {
      inp.focus();
    };

    const grp = el('div');
    grp.append(wrap, inp);
    return grp;

  } else if (type.kind === 'package') {
    const sel = el('select');
    const shells = [
      ['pkgs.bash', 'bash'],
      ['pkgs.zsh', 'zsh'],
      ['pkgs.fish', 'fish'],
      ['pkgs.nushell', 'nushell']
    ];

    for (const [val, lbl] of shells) {
      const o = el('option', { value: val }, lbl);
      if (val === (opt.default || 'pkgs.zsh')) {
        o.selected = true;
      }
      sel.appendChild(o);
    }

    if (stateTarget) {
      stateTarget[key] = sel.value;
    }

    sel.onchange = function () {
      if (stateTarget) {
        stateTarget[key] = sel.value;
      }
    };

    return sel;

  } else {
    const inputType = (opt.id || '').includes('email') ? 'email' : 'text';
    const inp = el('input', {
      type: inputType,
      placeholder: opt.placeholder ||
        (opt.example ? String(Array.isArray(opt.example) ? opt.example[0] : opt.example) : '')
    });

    if (opt.uppercase) {
      inp.style.textTransform = 'uppercase';
    }

    const def = (opt.hasDefault && opt.default !== null) ? String(opt.default) : '';
    const currentVal = (stateTarget && stateTarget[key] != null) ? stateTarget[key] : def;
    inp.value = currentVal;

    if (stateTarget) {
      stateTarget[key] = currentVal;
    }

    inp.oninput = function () {
      let v = inp.value;
      if (opt.uppercase) {
        v = v.toUpperCase();
      }
      if (stateTarget) {
        stateTarget[key] = v;
      }
      if (opt.onInput) {
        opt.onInput(v);
      }
    };

    return inp;
  }
}


function renderField(panelKey, opt) {
  const group = el('div', { class: 'field-group' });
  const lbl = el('label');

  lbl.textContent = opt.label || opt.id.split('.').pop();

  if (opt.required) {
    lbl.appendChild(el('span', { class: 'required' }, ' *'));
  }

  if (!opt.required && !opt.hasDefault) {
    lbl.appendChild(el('span', { class: 'hint' }, ' optionnel'));
  }

  if (opt.description) {
    const tip = el('span', { class: 'tooltip' });
    tip.append(
      el('span', { class: 'tooltip-icon' }, '?'),
      el('span', { class: 'tooltip-text' }, opt.description)
    );
    lbl.appendChild(tip);
  }

  group.appendChild(lbl);
  group.appendChild(renderInputFor(opt, state[panelKey], opt.id));

  if (opt.info) {
    group.appendChild(el('div', { class: 'info-row' }, opt.info));
  }

  return group;
}

function renderSection(panelKey, sectionLabel, fields) {
  const frag = document.createDocumentFragment();
  frag.appendChild(el('div', { class: 'divider' }));

  const labelEl = el('div', { class: 'section-label' });
  labelEl.textContent = sectionLabel;
  frag.appendChild(labelEl);

  for (const f of fields) {
    frag.appendChild(renderField(panelKey, f));
  }

  return frag;
}


function buildUserPanel(options) {
  const body = document.getElementById('user-panel-body');
  body.innerHTML = '';

  for (const s of FIXED_USER_FIELDS) {
    body.appendChild(renderSection('user', s.section, s.fields));
  }

  const toRow = function (o) {
    return Object.assign({}, o, { id: o.path, label: o.path.split('.').pop() });
  };

  const u2fPaths = new Set(['securix.self.u2f_keys']);
  const reqPaths = new Set(['securix.self.allowedVPNs', 'securix.self.teams']);
  const optPaths = new Set(['securix.self.hashedPassword', 'securix.self.defaultLoginShell', 'securix.self.bit']);

  const u2f = options.filter(function (o) { return u2fPaths.has(o.path) && !o.internal; });
  const req  = options.filter(function (o) { return reqPaths.has(o.path) && !o.internal; });
  const opt  = options.filter(function (o) { return optPaths.has(o.path) && !o.internal; });

  if (u2f.length) {
    body.appendChild(renderSection('user', 'Clés U2F', u2f.map(function (o) {
      return Object.assign(toRow(o));
    })));
  }

  if (req.length) {
    body.appendChild(renderSection('user', 'Sécurité & Accès', req.map(toRow)));
  }

  if (opt.length) {
    body.appendChild(renderSection('user', 'Optionnel', opt.map(function (o) {
      return Object.assign(toRow(o), { required: false, hasDefault: true });
    })));
  }
}

function buildMachinePanel(options) {
  const body = document.getElementById('machine-panel-body');
  body.innerHTML = '';

  for (const s of FIXED_MACHINE_FIELDS) {
    body.appendChild(renderSection('machine', s.section, s.fields));
  }

  const toRow = function (o) {
    return Object.assign({}, o, { id: o.path, label: o.path.split('.').pop(), required: !o.hasDefault });
  };

  const mainDiskOpt = options.find(function (o) { return o.path === 'securix.self.mainDisk'; });

  const diskField = mainDiskOpt
    ? [Object.assign({}, mainDiskOpt, {
        id: mainDiskOpt.path,
        label: 'Disque principal',
        type: { kind: 'enum', values: ['/dev/nvme0n1', '/dev/sda', '/dev/vda'] },
        default: '/dev/nvme0n1',
        hasDefault: true,
        required: true
      })]
    : [];

  const reqPaths = new Set(['securix.self.hardwareSKU']);
  const optPaths = new Set([
    'securix.self.inventoryId',
    'securix.self.infraRepositoryPath',
    'securix.self.infraRepositorySubdir'
  ]);

  const req = options.filter(function (o) { return reqPaths.has(o.path) && !o.internal; });
  const opt = options.filter(function (o) { return optPaths.has(o.path) && !o.internal; });

  if (diskField.length || req.length) {
    body.appendChild(renderSection('machine', 'Configuration', diskField.concat(req.map(toRow))));
  }

  if (opt.length) {
    body.appendChild(renderSection('machine', 'Optionnel', opt.map(function (o) {
      return Object.assign(toRow(o), { required: false, hasDefault: true });
    })));
  }

  body.appendChild(renderSection('machine', 'Utilisateurs assignés', [
    {
      id: '_machine.users',
      label: 'users',
      type: { kind: 'list' },
      placeholder: 'ex: dtintin, alice',
      description: 'Usernames des comptes utilisateur assignés à cette machine.'
    }
  ]));
}

function buildAdvPanel(options) {
  const body = document.getElementById('adv-panel-body');
  body.innerHTML = '';

  const advOpts = options.filter(function (o) {
    return !o.path.startsWith('securix.self.') && !o.internal;
  });

  if (!advOpts.length) {
    const msg = el('div', { class: 'info-row' });
    msg.style.padding = '20px';
    msg.textContent = 'Aucune option de module disponible.';
    body.appendChild(msg);
    updateAdvCount();
    return;
  }

  const groups = {};
  for (const o of advOpts) {
    const g = o.path.split('.').slice(0, 2).join('.');
    if (!groups[g]) {
      groups[g] = [];
    }
    groups[g].push(o);
  }

  for (const [name, opts] of Object.entries(groups)) {
    body.appendChild(buildAdvGroup(name, opts));
  }

  updateAdvCount();
}

function buildAdvGroup(groupName, opts) {
  if (!advGroupState[groupName]) {
    advGroupState[groupName] = { enabled: false, target: 'user' };
  }

  const gs = advGroupState[groupName];

  const wrap = el('div', { class: 'adv-group' + (gs.enabled ? ' enabled' : ''), id: 'adv-group-' + groupName });
  const header = el('div', { class: 'adv-group-header' });
  const checkbox = el('div', { class: 'adv-checkbox', id: 'adv-gcb-' + groupName }, gs.enabled ? '✓' : '');
  const nameEl = el('div', { class: 'adv-group-name' }, groupName);

  const btnUser = el('button', { class: 'adv-target-btn' + (gs.target === 'user' ? ' active-user' : '') }, 'user');
  const btnMachine = el('button', { class: 'adv-target-btn' + (gs.target === 'machine' ? ' active-machine' : '') }, 'machine');
  const targetToggle = el('div', { class: 'adv-target-toggle' });

  btnUser.onclick = function (e) {
    e.stopPropagation();
    setAdvGroupTarget(groupName, 'user');
  };

  btnMachine.onclick = function (e) {
    e.stopPropagation();
    setAdvGroupTarget(groupName, 'machine');
  };

  targetToggle.append(btnUser, btnMachine);

  header.onclick = function (e) {
    if (e.target !== btnUser && e.target !== btnMachine) {
      toggleAdvGroup(groupName);
    }
  };

  header.append(checkbox, nameEl, targetToggle);
  wrap.appendChild(header);

  const groupBody = el('div', { class: 'adv-group-body', id: 'adv-gbody-' + groupName });
  const subOpts = opts.filter(function (o) { return !o.path.endsWith('.enable'); });

  if (!subOpts.length) {
    const noOpt = el('div');
    noOpt.style.cssText = 'padding:8px 12px;font-size:13px;color:var(--muted);font-family:var(--mono)';
    noOpt.textContent = 'Aucune sous-option configurable.';
    groupBody.appendChild(noOpt);
  }

  for (const opt of subOpts) {
    if (!advState[opt.path]) {
      advState[opt.path] = { enabled: false, value: null };
    }

    const s = advState[opt.path];

    const subRow = el('div', { class: 'adv-suboption' + (s.enabled ? ' checked' : ''), id: 'adv-sub-' + opt.path });
    const subCb = el('div', { class: 'adv-sub-checkbox', id: 'adv-scb-' + opt.path }, s.enabled ? '✓' : '');
    const subLabel = el('div', { class: 'adv-sub-label' }, opt.path.split('.').pop());
    subLabel.title = opt.description || opt.path;

    subRow.append(subCb, subLabel);
    subRow.onclick = function () {
      toggleAdvSub(opt.path);
    };

    groupBody.appendChild(subRow);

    const subField = el('div', { class: 'adv-sub-field' + (s.enabled ? ' visible' : ''), id: 'adv-sf-' + opt.path });
    subField.appendChild(renderInputFor(opt, s, 'value'));
    groupBody.appendChild(subField);
  }

  wrap.appendChild(groupBody);
  return wrap;
}


function toggleAdvGroup(groupName) {
  const gs = advGroupState[groupName];
  gs.enabled = !gs.enabled;
  document.getElementById('adv-group-' + groupName).classList.toggle('enabled', gs.enabled);
  document.getElementById('adv-gcb-' + groupName).textContent = gs.enabled ? '✓' : '';
  updateAdvCount();
}

function setAdvGroupTarget(groupName, target) {
  advGroupState[groupName].target = target;

  document.getElementById('adv-group-' + groupName)
    .querySelectorAll('.adv-target-btn')
    .forEach(function (b) {
      b.className = 'adv-target-btn';
      if (b.textContent === 'user' && target === 'user') {
        b.classList.add('active-user');
      }
      if (b.textContent === 'machine' && target === 'machine') {
        b.classList.add('active-machine');
      }
    });
}

function toggleAdvSub(path) {
  const s = advState[path];
  s.enabled = !s.enabled;
  document.getElementById('adv-sub-' + path).classList.toggle('checked', s.enabled);
  document.getElementById('adv-scb-' + path).textContent = s.enabled ? '✓' : '';

  const subField = document.getElementById('adv-sf-' + path);
  if (subField) {
    subField.classList.toggle('visible', s.enabled);
  }
}

function updateAdvCount() {
  const count = Object.values(advGroupState).filter(function (s) { return s.enabled; }).length;
  document.getElementById('adv-count').textContent = count + ' module(s) activé(s)';
}


function nixStr(s) {
  return '"' + s + '"';
}

function nixList(arr) {
  if (!arr || !arr.length) {
    return '[ ]';
  }
  return '[ ' + arr.map(nixStr).join(' ') + ' ]';
}

function generateAdvNixLines(target) {
  const lines = [];

  for (const [groupName, gs] of Object.entries(advGroupState)) {
    if (!gs.enabled || gs.target !== target) {
      continue;
    }

    const hasEnable = securixOptions.some(function (o) { return o.path === groupName + '.enable'; });
    if (hasEnable) {
      lines.push('  ' + groupName + '.enable = true;');
    }

    for (const [path, s] of Object.entries(advState)) {
      if (!s.enabled || !path.startsWith(groupName + '.') || s.value == null || s.value === '') {
        continue;
      }

      const opt = securixOptions.find(function (o) { return o.path === path; });
      if (!opt) {
        continue;
      }

      const k = opt.type && opt.type.kind;

      if (k === 'bool') {
        lines.push('  ' + path + ' = ' + s.value + ';');
      } else if (k === 'list') {
        lines.push('  ' + path + ' = ' + nixList(Array.isArray(s.value) ? s.value : []) + ';');
      } else if (k === 'package') {
        lines.push('  ' + path + ' = ' + s.value + ';');
      } else if (s.value) {
        lines.push('  ' + path + ' = ' + nixStr(s.value) + ';');
      }
    }
  }

  return lines;
}

function generateUserNix() {
  const username = (getValue('user', 'securix.self.user.username') || '').trim();
  const email    = (getValue('user', 'securix.self.user.email') || '').trim();
  const hpVal    = getValue('user', 'securix.self.hashedPassword');

  const lines = [
    '{ pkgs, ... }:',
    '{',
    '  securix.self.user = {',
    '    email = ' + nixStr(email) + ';',
    '    username = ' + nixStr(username) + ';',
    '    hashedPassword = ' + nixStr(hpVal && hpVal !== '!' ? hpVal : '!') + ';'
  ];

  const OPTS = new Set([
    'securix.self.u2f_keys',
    'securix.self.allowedVPNs',
    'securix.self.teams',
    'securix.self.defaultLoginShell',
    'securix.self.bit'
  ]);

  for (const opt of securixOptions) {
    if (!OPTS.has(opt.path) || opt.internal) {
      continue;
    }

    const key = opt.path.replace('securix.self.', '');
    const val = getValue('user', opt.path);
    const k = opt.type && opt.type.kind;

    if (k === 'bool') {
      lines.push('    ' + key + ' = ' + val + ';');
    } else if (k === 'list') {
      const arr = val || [];
      if (key === 'u2f_keys' && arr.length) {
        lines.push('    ' + key + ' = [\n' + arr.map(function (v) { return '      ' + nixStr(v); }).join('\n') + '\n    ];');
      } else {
        lines.push('    ' + key + ' = ' + nixList(arr) + ';');
      }
    } else if (k === 'package') {
      if (val) {
        lines.push('    ' + key + ' = ' + val + ';');
      }
    } else if (k === 'enum') {
      if (val) {
        lines.push('    ' + key + ' = ' + nixStr(val) + ';');
      }
    } else if (val && val !== (opt.hasDefault ? String(opt.default) : '')) {
      lines.push('    ' + key + ' = ' + nixStr(val) + ';');
    }
  }

  lines.push('  };');
  lines.push.apply(lines, generateAdvNixLines('user'));
  lines.push('}');

  return lines.join('\n') + '\n';
}

function generateMachineNix() {
  const sn    = (getValue('machine', 'securix.self.machine.serialNumber') || '').toUpperCase().trim();
  const disk  = getValue('machine', 'securix.self.mainDisk') || '/dev/nvme0n1';
  const users = getValue('machine', '_machine.users') || [];

  const lines = [
    '{',
    '  securix.self.mainDisk = ' + nixStr(disk) + ';',
    '  securix.self.machine = {',
    '    serialNumber = ' + nixStr(sn) + ';'
  ];

  const OPTS = new Set([
    'securix.self.hardwareSKU',
    'securix.self.inventoryId',
    'securix.self.infraRepositoryPath',
    'securix.self.infraRepositorySubdir'
  ]);

  for (const opt of securixOptions) {
    if (!OPTS.has(opt.path) || opt.internal) {
      continue;
    }

    const key = opt.path.replace('securix.self.', '');
    const val = getValue('machine', opt.path);
    const k = opt.type && opt.type.kind;

    if (k === 'bool') {
      lines.push('    ' + key + ' = ' + val + ';');
    } else if (k === 'list') {
      lines.push('    ' + key + ' = ' + nixList(val || []) + ';');
    } else if (k === 'enum') {
      if (val) {
        lines.push('    ' + key + ' = ' + nixStr(val) + ';');
      }
    } else if (val && val !== (opt.hasDefault ? String(opt.default) : '')) {
      lines.push('    ' + key + ' = ' + nixStr(val) + ';');
    }
  }

  if (users.length) {
    lines.push('    users = ' + nixList(users) + ';');
  } else {
    lines.push('    users = [ ]; # aucun utilisateur assigné');
  }

  lines.push('  };');
  lines.push.apply(lines, generateAdvNixLines('machine'));
  lines.push('}');

  return lines.join('\n') + '\n';
}

function highlight(code) {
  return code
    .replace(/(#.*)/g, '<span class="nix-comment">$1</span>')
    .replace(/(\"(?:[^\"\\]|\\.)*\")/g, '<span class="nix-str">$1</span>')
    .replace(/\b(true)\b/g, '<span class="nix-bool-true">true</span>')
    .replace(/\b(false)\b/g, '<span class="nix-bool-false">false</span>');
}


function addTag(wrapId, val, inp) {
  tagState[wrapId].push(val);
  if (inp) {
    inp.value = '';
  }
  renderTags(wrapId);
}

function removeTag(wrapId, idx) {
  tagState[wrapId].splice(idx, 1);
  renderTags(wrapId);
}

function renderTags(wrapId) {
  const wrap = document.getElementById(wrapId);
  if (!wrap) {
    return;
  }

  wrap.querySelectorAll('.tag, .tag-hint').forEach(function (t) { t.remove(); });

  const arr = tagState[wrapId];

  if (!arr.length) {
    wrap.appendChild(el('div', { class: 'tag-hint' }, 'Entrée pour valider'));
    return;
  }

  arr.forEach(function (v, i) {
    const tag = el('div', { class: 'tag' });
    const span = el('span');
    span.title = v;
    span.textContent = v.length > 40 ? v.slice(0, 38) + '…' : v;

    const rm = el('span', { class: 'tag-remove' }, '×');
    rm.onclick = function (e) {
      e.stopPropagation();
      removeTag(wrapId, i);
    };

    tag.append(span, rm);
    wrap.appendChild(tag);
  });
}


function getValue(panelKey, optId) {
  const wrapId = 'wrap-' + panelKey + '__' + optId;
  return (tagState[wrapId] !== undefined) ? tagState[wrapId] : state[panelKey][optId];
}

function resetPanel(panelKey) {
  state[panelKey] = {};

  for (const [wrapId, arr] of Object.entries(tagState)) {
    if (wrapId.includes(panelKey + '__') || wrapId.includes('wrap-' + panelKey)) {
      arr.length = 0;
      renderTags(wrapId);
    }
  }

  if (panelKey === 'user') {
    buildUserPanel(securixOptions);
  } else {
    buildMachinePanel(securixOptions);
  }

  buildAdvPanel(securixOptions);
}


function previewUser() {
  const username = (getValue('user', 'securix.self.user.username') || '').trim();

  if (!username) {
    setStatus('u-status', '× username requis', true);
    return;
  }

  currentContent  = generateUserNix();
  currentFilename = username + '.nix';
  showModal('inventory/users/' + currentFilename, currentContent);
  setStatus('u-status', '');
}

function previewMachine() {
  const sn = (getValue('machine', 'securix.self.machine.serialNumber') || '').trim();

  if (!sn) {
    setStatus('m-status', '× numéro de série requis', true);
    return;
  }

  currentContent  = generateMachineNix();
  currentFilename = sn.toUpperCase() + '.nix';
  showModal('inventory/machines/' + currentFilename, currentContent);
  setStatus('m-status', '');
}

function showModal(title, content) {
  document.getElementById('modal-title').textContent = title;
  document.getElementById('modal-content').innerHTML = highlight(content);
  document.getElementById('modal').classList.add('visible');
}

function saveFile() {
  const blob = new Blob([currentContent], { type: 'text/plain' });
  const a = document.createElement('a');
  a.href = URL.createObjectURL(blob);
  a.download = currentFilename;
  a.click();
  URL.revokeObjectURL(a.href);
}

function copyContent() {
  navigator.clipboard.writeText(currentContent).then(function () {
    const btn = document.querySelector('.modal-footer .btn-secondary');
    const orig = btn.textContent;
    btn.textContent = 'Copié !';
    setTimeout(function () {
      btn.textContent = orig;
    }, 1500);
  });
}

function closeModal(e) {
  if (e.target === document.getElementById('modal')) {
    closeModalBtn();
  }
}

function closeModalBtn() {
  document.getElementById('modal').classList.remove('visible');
}

function setStatus(id, msg, err) {
  const e = document.getElementById(id);
  e.textContent = msg;
  e.className = 'status' + (err ? ' err' : (msg ? ' ok' : ''));
}


const FALLBACK_OPTIONS = [
  { path: 'securix.self.mainDisk', type: { kind: 'str' }, description: 'Disque du système', example: '/dev/nvme0n1', hasDefault: false, internal: false },
  { path: 'securix.self.u2f_keys', type: { kind: 'list' }, description: 'Clés U2F', default: [], hasDefault: true, internal: false },
  { path: 'securix.self.allowedVPNs', type: { kind: 'list' }, description: 'VPNs autorisés', default: [], hasDefault: true, internal: false },
  { path: 'securix.self.teams', type: { kind: 'list' }, description: 'Équipes', default: [], hasDefault: true, internal: false },
  { path: 'securix.self.machine.hardwareSKU', type: { kind: 'enum', values: ['x280', 'elitebook645g11', 'latitude5340', 't14g6', 'x9-15', 'e14-g7'] }, description: 'Identifiant matériel', hasDefault: false, internal: false },
  { path: 'securix.self.machine.inventoryId', type: { kind: 'int' }, description: "Numéro d'inventaire", hasDefault: false, internal: false },
  { path: 'securix.self.machine.users', type: { kind: 'list' }, description: 'Utilisateurs assignés', default: [], hasDefault: true, internal: false }
];

function loadOptions() {
  const data = @@SECURIX_OPTIONS@@;
  securixOptions = data.options || FALLBACK_OPTIONS;

  for (const opt of securixOptions) {
    if (opt.isEnable === undefined) {
      opt.isEnable = opt.path.endsWith('.enable');
    }
    if (opt.enableGroup === undefined) {
      const g = opt.path.split('.').slice(0, -1).join('.');
      opt.enableGroup = securixOptions.some(function (o) { return o.path === g + '.enable'; }) ? g : null;
    }
  }

  buildUserPanel(securixOptions);
  buildAdvPanel(securixOptions);
  buildMachinePanel(securixOptions);
}

document.addEventListener('keydown', function (e) {
  if (e.key === 'Escape') {
    closeModalBtn();
  }
});

loadOptions();