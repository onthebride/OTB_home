-- 알림톡 「보냈는지 확인」을 1분마다 → 3분마다.
--
-- 왜. cron.job_run_details 가 11MB / 15,150줄인데 그중 11,102줄(73%)이 이 작업 하나다.
-- 8일 동안 65,202번 돌았고, 그 대부분은 볼 게 없어 그냥 끝난다.
-- 로그가 쌓이니 청소(private.cron_log_prune)의 count(*) 가 한 번에 평균 229ms 를 쓴다.
--
-- 늦어지는 것은. private.alimtalk_retry_due() 가 하는 일은 «보낸 것의 답이 왔나» 보는 것이다.
-- 손님에게 나가는 시각이 늦어지는 게 아니라, 「보냈다 → 도착했다」로 표시가 바뀌는 게
-- 최대 2분 늦어질 뿐이다. 화면에서 티가 나지 않는다.
--
-- 실패 처리도 그대로 돈다. 함수 안의 기준이 시각(interval)이지 «몇 번째 실행»이 아니다.
--   · 확실한 실패 → 최대 3번 재발송. 3분 간격이면 9분 안에 끝난다
--   · 무응답 → 15분 지나면 포기. 3분마다 보므로 그 사이 다섯 번 본다
--
-- jobid 를 박지 않는다 — 작업을 지웠다 다시 넣으면 번호가 바뀐다. 명령으로 찾는다.

do $$
declare jid bigint; old text;
begin
  select jobid, schedule into jid, old
    from cron.job where command like '%alimtalk_retry_due%';

  if jid is null then
    raise exception '알림톡 재시도 작업을 못 찾았다 — 이름이 바뀌었나 확인할 것';
  end if;

  perform cron.alter_job(jid, schedule => '*/3 * * * *');
  raise notice '알림톡 재시도(jobid %) 간격 % → */3 * * * *', jid, old;
end $$;
