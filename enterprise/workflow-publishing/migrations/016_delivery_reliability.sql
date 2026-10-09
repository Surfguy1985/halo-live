-- Future CAS integration. No role grants or automatic migration execution.
ALTER TABLE halo_execution.dispatch_permits
 ADD COLUMN lease_token text;
ALTER TABLE halo_execution.consumer_deliveries
 ADD COLUMN outcome text CHECK (outcome IN ('acknowledged','rejected','uncertain')),
 ADD COLUMN outcome_updated_at timestamptz;
-- Delivery receipt must be bound to the same event+tenant+consumer+lease token.
-- Do not auto-retry uncertain events without a receiving-system idempotency
-- guarantee on (tenant_id,consumer_id,event_id).
