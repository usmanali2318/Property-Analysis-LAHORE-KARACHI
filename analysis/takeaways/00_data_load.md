DATA LOAD
I started with 67,973 monthly price records from Zameen.com's official price index, covering Lahore and Karachi, houses and flats, from January 2011 to August 2026. The data was complete, with no missing values, no duplicates and no gaps in the timeline.
Zameen has no data for some plot sizes, so it fills those pages with the same fake price history repeated. I proved this by comparing the histories month by month and found every fake one identical. The affected sizes are 8, 12 and 14 Marla and 4, 8, 10 and 20 Kanal in both cities. For houses these sizes exist in real life, the index just has no data for them.
I also dropped two real but unreliable histories, Lahore 1 and 2 Kanal flats, where 1 Kanal flats cost less than 3 Marla ones and 2 Kanal flats were priced in the billions.
In total 30 of 592 price histories (about 8% of records) were set aside, not deleted. I chose not to estimate the missing sizes from neighbouring ones, since that would be invented data.
