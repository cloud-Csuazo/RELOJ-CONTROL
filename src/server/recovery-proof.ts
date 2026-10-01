import 'server-only';
import { createHmac, timingSafeEqual } from 'node:crypto';
import { config } from './config';
export function recoveryProof(userId:string) {
  const payload=`${userId}:${Date.now()}`;
  return `${payload}:${createHmac('sha256',config().RATE_LIMIT_HMAC_SECRET).update(`recovery:${payload}`).digest('hex')}`;
}
export function validRecoveryProof(proof:string|undefined,userId:string) {
  if(!proof)return false;
  const [id,time,signature]=proof.split(':');
  if(id!==userId||!/^\d+$/.test(time??'')||!signature||Date.now()-Number(time)>600000||Date.now()<Number(time))return false;
  const expected=createHmac('sha256',config().RATE_LIMIT_HMAC_SECRET).update(`recovery:${id}:${time}`).digest('hex');
  return signature.length===expected.length&&timingSafeEqual(Buffer.from(signature),Buffer.from(expected));
}
