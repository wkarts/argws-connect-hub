export const debounce = (func, wait, immediate = false) => {
  let timeout;
  return function debounced(...args) {
    const context = this;
    const callNow = immediate && !timeout;
    clearTimeout(timeout);
    timeout = setTimeout(() => {
      timeout = null;
      if (!immediate) func.apply(context, args);
    }, wait);
    if (callNow) return func.apply(context, args);
    return undefined;
  };
};

const normalizeHex = value => {
  if (typeof value !== 'string') return null;
  const input = value.trim();
  const short = input.match(/^#([0-9a-f]{3})$/i);
  if (short) return short[1].split('').map(ch => ch + ch).join('');
  const full = input.match(/^#([0-9a-f]{6})$/i);
  return full ? full[1] : null;
};

const parseRgb = value => {
  const hex = normalizeHex(value);
  if (hex) {
    return [0, 2, 4].map(index => parseInt(hex.slice(index, index + 2), 16));
  }
  if (typeof value !== 'string') return null;
  const match = value.match(/rgba?\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)/i);
  return match ? match.slice(1, 4).map(Number) : null;
};

export const getContrastingTextColor = background => {
  const rgb = parseRgb(background);
  if (!rgb) return '#ffffff';
  const [r, g, b] = rgb.map(channel => channel / 255);
  const linear = [r, g, b].map(channel =>
    channel <= 0.03928
      ? channel / 12.92
      : ((channel + 0.055) / 1.055) ** 2.4
  );
  const luminance = 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2];
  return luminance > 0.45 ? '#111827' : '#ffffff';
};

export const formatTime = secondsValue => {
  const total = Math.max(0, Number(secondsValue) || 0);
  const hours = Math.floor(total / 3600);
  const minutes = Math.floor((total % 3600) / 60);
  const seconds = Math.floor(total % 60);
  const pieces = [];
  if (hours) pieces.push(`${hours}h`);
  if (minutes || hours) pieces.push(`${minutes}m`);
  if (!hours && !minutes) pieces.push(`${seconds}s`);
  return pieces.join(' ');
};

export const trimContent = (content = '', maxLength = 1024, ellipsis = false) => {
  const value = String(content || '');
  if (value.length <= maxLength) return value;
  const suffix = ellipsis && maxLength > 1 ? '…' : '';
  return `${value.slice(0, Math.max(0, maxLength - suffix.length))}${suffix}`;
};

export const parseBoolean = candidate => {
  if (typeof candidate === 'boolean') return candidate;
  if (typeof candidate === 'number') return candidate === 1;
  return ['true', '1', 'yes', 'on'].includes(String(candidate).trim().toLowerCase());
};

export const convertSecondsToTimeUnit = (secondsValue, unitNames) => {
  const seconds = Number(secondsValue);
  if (!Number.isFinite(seconds) || seconds <= 0) return { time: '', unit: '' };
  const units = [
    { key: 'day', seconds: 86400 },
    { key: 'hour', seconds: 3600 },
    { key: 'minute', seconds: 60 },
  ];
  const exact = units.find(unit => seconds % unit.seconds === 0);
  const selected = exact || units.find(unit => seconds >= unit.seconds) || units[2];
  const raw = seconds / selected.seconds;
  const time = Number.isInteger(raw) ? raw : Number(raw.toFixed(2));
  return { time, unit: unitNames[selected.key] };
};

export const sortAsc = values => [...values].sort((a, b) => a - b);

export const quantile = (values, q) => {
  const sorted = sortAsc((values || []).filter(value => Number.isFinite(Number(value))).map(Number));
  if (!sorted.length) return 0;
  if (q <= 0) return sorted[0];
  if (q >= 1) return sorted[sorted.length - 1];
  const position = (sorted.length - 1) * q;
  const base = Math.floor(position);
  const rest = position - base;
  return sorted[base + 1] === undefined
    ? sorted[base]
    : sorted[base] + rest * (sorted[base + 1] - sorted[base]);
};

export const getQuantileIntervals = (data, intervals) =>
  (intervals || []).map(interval => quantile(data || [], interval));

const firstName = name => String(name || '').trim().split(/\s+/)[0] || '';
const lastName = name => {
  const parts = String(name || '').trim().split(/\s+/).filter(Boolean);
  return parts.length > 1 ? parts[parts.length - 1] : '';
};

export const getMessageVariables = ({ conversation = {}, contact = null } = {}) => {
  const sender = contact || conversation?.meta?.sender || {};
  const agent = conversation?.meta?.assignee || {};
  return {
    'contact.name': sender.name || '',
    'contact.first_name': firstName(sender.name),
    'contact.last_name': lastName(sender.name),
    'contact.email': sender.email,
    'contact.phone': sender.phone_number,
    'contact.id': sender.id,
    'conversation.id': conversation.id,
    'agent.name': agent.name || '',
    'agent.first_name': firstName(agent.name),
    'agent.last_name': lastName(agent.name),
    'agent.email': agent.email,
  };
};

const VARIABLE_PATTERN = /{{\s*([^{}]+?)\s*}}/g;

export const replaceVariablesInMessage = ({ message = '', variables = {} } = {}) =>
  String(message).replace(VARIABLE_PATTERN, (token, name) => {
    const key = name.trim();
    const value = variables[key];
    return value === undefined || value === null || value === '' ? token : String(value);
  });

export const getUndefinedVariablesInMessage = ({ message = '', variables = {} } = {}) => {
  const missing = new Set();
  String(message).replace(VARIABLE_PATTERN, (_token, name) => {
    const key = name.trim();
    const value = variables[key];
    if (value === undefined || value === null || value === '') missing.add(key);
    return _token;
  });
  return [...missing];
};

export const createTypingIndicator = (onStartTyping, onStopTyping, idleTime = 4000) => {
  let timer = null;
  let active = false;
  const stop = () => {
    if (timer) clearTimeout(timer);
    timer = null;
    if (active) {
      active = false;
      onStopTyping?.();
    }
  };
  const start = () => {
    if (!active) {
      active = true;
      onStartTyping?.();
    }
    if (timer) clearTimeout(timer);
    timer = setTimeout(stop, idleTime);
  };
  return { start, stop };
};

const formatRemaining = secondsValue => {
  const seconds = Math.abs(Math.round(secondsValue));
  if (seconds >= 86400) return `${Math.ceil(seconds / 86400)}d`;
  if (seconds >= 3600) return `${Math.ceil(seconds / 3600)}h`;
  if (seconds >= 60) return `${Math.ceil(seconds / 60)}m`;
  return `${seconds}s`;
};

const candidateSla = ({ type, baseTime, threshold, now }) => {
  const numericThreshold = Number(threshold);
  const numericBase = Number(baseTime);
  if (!numericThreshold || !numericBase) return null;
  const dueAt = numericBase + numericThreshold;
  const remaining = dueAt - now;
  return {
    type,
    dueAt,
    remaining,
    threshold: formatRemaining(remaining),
    isSlaMissed: remaining < 0,
    icon: remaining < 0 ? 'alert-triangle' : 'clock',
  };
};

export const evaluateSLAStatus = ({ appliedSla = {}, chat = {} } = {}) => {
  if (!appliedSla) return { type: null, threshold: null, icon: null, isSlaMissed: false };
  const now = Math.floor(Date.now() / 1000);
  const createdAt = Number(chat.created_at || chat.timestamp || 0);
  const waitingSince = Number(chat.waiting_since || 0);
  const firstReplyAt = Number(chat.first_reply_created_at || 0);
  const candidates = [];

  if (!firstReplyAt) {
    candidates.push(candidateSla({
      type: 'frt',
      baseTime: createdAt,
      threshold: appliedSla.sla_first_response_time_threshold ?? appliedSla.first_response_time_threshold,
      now,
    }));
  }

  if (waitingSince) {
    candidates.push(candidateSla({
      type: 'nrt',
      baseTime: waitingSince,
      threshold: appliedSla.sla_next_response_time_threshold ?? appliedSla.next_response_time_threshold,
      now,
    }));
  }

  if (!['resolved', 'closed'].includes(chat.status)) {
    candidates.push(candidateSla({
      type: 'rt',
      baseTime: createdAt,
      threshold: appliedSla.sla_resolution_time_threshold ?? appliedSla.resolution_time_threshold,
      now,
    }));
  }

  const valid = candidates.filter(Boolean);
  if (!valid.length) return { type: null, threshold: null, icon: null, isSlaMissed: false };
  valid.sort((a, b) => a.remaining - b.remaining);
  return valid[0];
};
