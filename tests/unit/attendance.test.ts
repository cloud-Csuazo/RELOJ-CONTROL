import {test} from 'node:test';
import assert from 'node:assert/strict';
import {transition,workMilliseconds} from '../../src/modules/attendance/domain';
test('invalid double marks and unmatched breaks rejected',()=>{assert.equal(transition('WORKING','CLOCK_IN'),null);assert.equal(transition('IDLE','BREAK_END'),null);assert.equal(transition('BREAK','CLOCK_OUT'),null);assert.equal(transition('BREAK','BREAK_END'),'WORKING');});
test('worked time excludes lunch and uses event timestamps',()=>{const stamp=(n:number)=>new Date(n*60000).toISOString();assert.equal(workMilliseconds([{event_type:'CLOCK_IN',timestamp_server:stamp(0)},{event_type:'BREAK_START',timestamp_server:stamp(60)},{event_type:'BREAK_END',timestamp_server:stamp(90)},{event_type:'CLOCK_OUT',timestamp_server:stamp(150)}],150*60000),120*60000);});
