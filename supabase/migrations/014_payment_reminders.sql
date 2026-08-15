-- Payment Reminder — runs every hour, sends SMS to customers with unpaid orders
-- Requires pg_cron and pg_net extensions enabled

-- Schedule: every hour at minute 15
SELECT cron.schedule(
  'payment-reminder',
  '15 * * * *',
  $$
  SELECT net.http_post(
    url := 'https://nyrjuuynklrmyzgsgmwm.supabase.co/functions/v1/charge-momo?action=remind',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer YOUR_TAGITELA_ANON_KEY'
    ),
    body := '{}'::jsonb
  );
  $$
);

-- To check if it's working:
-- SELECT * FROM cron.job;

-- To remove the schedule:
-- SELECT cron.unschedule('payment-reminder');
