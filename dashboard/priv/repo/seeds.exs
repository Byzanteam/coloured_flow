# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inserts and starts the four demo flows used by the dashboard's operator,
# drawer, replay, and presentation stories. Idempotent: a second run
# reuses existing `Schemas.Flow` / `Schemas.Enactment` rows rather than
# inserting duplicates.
#
# See `ColouredFlowDashboard.Seed` for the cross-backend insert details
# and the public-API deviation notice.

ColouredFlowDashboard.Seed.run()
