'use strict';
/* CELL-65 :: background.js - сервис-воркер (MV3)
 * 1) сторож: alarm cell65_watch каждые 30 мин -> проверка здоровья 204,
 *    при сбое - переключение на следующий сервер по кольцу СПБ (зеркало h4/e7 скрипта);
 * 2) маршрутизатор команд: тяжёлые клетки выполняются ЗДЕСЬ (проба живёт,
 *    даже если попап закрыли; chrome.proxy - общий для профиля);
 * 3) бейдж значка: активное кольцо R1..R5 / R?. */

importScripts('cells.js');

/* ---- маршрутизатор команд попапа ---- */
chrome.runtime.onMessage.addListener(function (msg, sender, sendResponse) {
  (async function () {
    try {
      if (!msg || !msg.cmd) { sendResponse({ ok: false }); return; }
      if (msg.cmd === 'cell') {
        await C65.guard('клетка ' + msg.id, async function () { await C65.runCellId(msg.id); });
        sendResponse({ ok: true });
      } else if (msg.cmd === 'row') {
        await C65.guard('ряд ' + msg.row, async function () { await C65.runRow(msg.row); });
        sendResponse({ ok: true });
      } else if (msg.cmd === 'auto') {
        await C65.guard('авто-цикл', async function () { await C65.runAuto(); });
        sendResponse({ ok: true });
      } else if (msg.cmd === 'srv') {
        await C65.applyServerObj(msg.srv);
        sendResponse({ ok: true });
      } else if (msg.cmd === 'direct') {
        await C65.setDirect();
        sendResponse({ ok: true });
      } else if (msg.cmd === 'g2') {
        await C65.guard('g2 (включить сервер)', async function () { await C65.CELLS.g2(); });
        sendResponse({ ok: true });
      } else if (msg.cmd === 'watch') {
        await C65.watchToggle();
        sendResponse({ ok: true });
      } else if (msg.cmd === 'undo') {
        await C65.CELLS.h2();
        sendResponse({ ok: true });
      } else if (msg.cmd === 'report') {
        await C65.CELLS.h6();
        sendResponse({ ok: true });
      } else {
        sendResponse({ ok: false, err: 'нет команды ' + msg.cmd });
      }
    } catch (e) {
      sendResponse({ ok: false, err: (e && e.message) ? e.message : String(e) });
    }
  })();
  return true; /* ответ придёт асинхронно */
});

/* ---- сторож ---- */
chrome.alarms.onAlarm.addListener(function (alarm) {
  if (alarm && alarm.name === 'cell65_watch') {
    C65.watchTick();
  }
});

/* ---- бейдж ---- */
C65.restoreBadge = async function () {
  try {
    const act = await C65.stGet('active', null);
    if (act) {
      chrome.action.setBadgeText({ text: C65.badgeOf(act.ring) });
      chrome.action.setBadgeBackgroundColor({ color: '#0e7490' });
    } else {
      chrome.action.setBadgeText({ text: '' });
    }
  } catch (e) {}
};
chrome.runtime.onInstalled.addListener(function () { C65.restoreBadge(); });
chrome.runtime.onStartup.addListener(function () { C65.restoreBadge(); });
C65.restoreBadge();

/* ---- 407 без диалога (ext 2.2.0) ----
 * публичные списки идут без авторизации: 407 = кандидат/сервер мёртв.
 * запрос гасится сам - модальное окно «требуется имя пользователя и пароль»
 * больше не появляется ни во время пробы, ни после неё. */
C65.authKills = 0; C65.authLastTs = 0;
try {
  chrome.webRequest.onAuthRequired.addListener(function (details, cb) {
    C65.authKills++;
    const now = Date.now();
    if (now - C65.authLastTs > 30000) {
      C65.authLastTs = now;
      const who = (details && details.challenger && details.challenger.host) ? (details.challenger.host + ':' + details.challenger.port) : 'неизвестный';
      C65.log('i', 'прокси потребовал авторизацию (407): ' + who + ' - запрос отменён без окна ввода (всего: ' + C65.authKills + ')');
    }
    if (typeof cb === 'function') { cb({ cancel: true }); return; }
    return { cancel: true };
  }, { urls: ['<all_urls>'] }, ['asyncBlocking']);
} catch (e) {
  try { C65.log('!!', 'onAuthRequired не зарегистрирован: ' + (e && e.message ? e.message : e)); } catch (e2) {}
}
