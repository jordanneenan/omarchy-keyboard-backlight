// Exercise the actual QML controller functions with timer/process stand-ins.
const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const source = fs.readFileSync(require('node:path').join(__dirname, '../BarWidget.qml'), 'utf8');
function extract(name) {
  const start = source.indexOf('  function ' + name + '(');
  assert(start >= 0);
  const open = source.indexOf('{', start);
  let depth = 1, end = open + 1;
  for (; depth; end++) { if (source[end] === '{') depth++; if (source[end] === '}') depth--; }
  return source.slice(start, end);
}
const timer = () => ({running:false, starts:0, restart(){this.running=true;this.starts++}, stop(){this.running=false}});
function setup() {
  const c = {ambientEnabled:true, manualOverride:false, lockStateKnown:true, sessionLocked:false,
    startupReady:true, ambientAverage:100, ambientReading:100, ambientMode:'off', ambientHealthy:true,
    ambientGeneration:0, sampleGeneration:-1, ambientHelper:'/test/helper', darkThreshold:35, brightThreshold:105,
    ambientProc:{running:false}, ambientTimer:timer(), sampleRetry:timer(), Date, isFinite, Math,
    persistSettings(v){this.saved=v}};
  c.persistSettings = v => { c.saved=v };
  c.root=c; vm.createContext(c);
  for(const name of ['resetAmbient','sampleAmbient','updateLockState','setIntervalMinutes']) vm.runInContext(extract(name),c);
  return c;
}
let c=setup();c.updateLockState('true');assert(c.sessionLocked);assert(!c.ambientTimer.running);
c.sampleAmbient();assert(!c.ambientProc.running);
c.updateLockState('false');assert(c.ambientProc.running);assert.equal(c.ambientAverage,-1);assert.equal(c.ambientTimer.starts,1);
c.ambientProc.running=false;c.updateLockState('false');assert(!c.ambientProc.running);assert.equal(c.ambientTimer.starts,1);
c=setup();c.manualOverride=true;c.updateLockState('true');c.updateLockState('false');assert(!c.ambientProc.running);
c=setup();c.updateLockState('unavailable');c.sampleAmbient();assert(!c.lockStateKnown);assert(!c.ambientProc.running);
c.updateLockState('false');assert(c.ambientProc.running);
c=setup();c.ambientProc.running=true;c.updateLockState('true');c.updateLockState('false');assert(c.sampleRetry.running);
c.ambientProc.running=false;c.sampleAmbient();assert(!c.sampleRetry.running);assert(c.ambientTimer.running);
c=setup();c.ambientEnabled=false;c.updateLockState('true');c.updateLockState('false');assert(!c.ambientProc.running);
c=setup();c.setIntervalMinutes(10);assert.equal(c.saved.ambientIntervalMinutes,10);
c.setIntervalMinutes(0);assert.equal(c.saved.ambientIntervalMinutes,1);
c.setIntervalMinutes(1500);assert.equal(c.saved.ambientIntervalMinutes,1440);
c.setIntervalMinutes(NaN);assert.equal(c.saved.ambientIntervalMinutes,1440);
console.log('Session timing passed: lock/unlock, fresh average, duplicate polls, manual pause, unavailable status, in-flight retry, disabled mode, interval limits.');
