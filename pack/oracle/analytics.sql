-- route_load: Seat occupancy inputs for departed flights by route.
SELECT r.id, SUM(f.passengers) passengers,SUM(a.seats) seats FROM flights f JOIN routes r ON r.id=f.route_id JOIN aircraft a ON a.id=f.aircraft_id WHERE f.status='departed' GROUP BY r.id ORDER BY r.id;

-- turnaround: Average ground duration and missed targets per origin airport.
SELECT a.iata,AVG(t.ground_minutes*1.0) avg_minutes,SUM(CASE WHEN t.ground_minutes>t.target_minutes THEN 1 ELSE 0 END) missed FROM turnarounds t JOIN flights f ON f.id=t.flight_id JOIN routes r ON r.id=f.route_id JOIN airports a ON a.id=r.origin_id GROUP BY a.iata ORDER BY a.iata;

-- upgrade_flags: Count records marked by delay_flag after migration.
SELECT delay_flag,COUNT(*) records FROM flights GROUP BY delay_flag ORDER BY delay_flag;
