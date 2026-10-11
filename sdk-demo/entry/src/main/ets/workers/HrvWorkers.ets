import { ErrorEvent, MessageEvents, ThreadWorkerGlobalScope, worker } from '@kit.ArkTS';
import { HrvAnalyzer } from '@veepoo/vpble-sdk';

/**
 * HRV 洛伦兹计算 Worker
 *
 * 散点/星级/相似度三件套是重计算（数千 RR 点的纯 CPU 循环），必须在
 * 子线程执行——在 UI 线程直接调用会卡死页面（与主工程 HrvWorkers 同因同解）。
 * 消息协议：主线程 postMessage(JSON 字符串)，本线程回 postMessage(JSON 字符串)，
 * 字符串跨线程拷贝最稳，不依赖共享内存序列化行为。
 */

/** 主线程 → worker 的计算请求 */
export interface HrvWorkerRequest {
  data: number[];
  isRingDevice: boolean;
}

/** worker → 主线程的计算结果（三件套各自 JSON 序列化） */
export interface HrvWorkerResponse {
  scatter: string;
  star: string;
  similarity: string;
}

const workerPort: ThreadWorkerGlobalScope = worker.workerPort;

workerPort.onmessage = (event: MessageEvents) => {
  const req = JSON.parse(event.data) as HrvWorkerRequest;
  const rr = req.data;
  const isRing = req.isRingDevice === true;

  const scatter = HrvAnalyzer.getScatterPlot(rr, isRing);
  const star = HrvAnalyzer.getStarIndex(rr, isRing);
  const similarity = HrvAnalyzer.getSimilarity(rr, isRing);

  const resp: HrvWorkerResponse = {
    scatter: JSON.stringify(scatter),
    star: JSON.stringify(star),
    similarity: JSON.stringify(similarity),
  };
  workerPort.postMessage(JSON.stringify(resp));
};

workerPort.onmessageerror = () => {
  // 序列化失败等场景，仅留痕
  console.error('HrvWorkers onmessageerror');
};
