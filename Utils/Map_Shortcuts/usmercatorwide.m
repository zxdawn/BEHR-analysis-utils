%usmercatorwide - prepares a map of the US using the Mercator
%projection type, drawing the states and coastline in black. Uses the m_map
%package.  Lat/lon boundaries extended; useful for visualizing fuller
%satellite swaths

m_proj('Mercator','lonj',[-135 -55],'lat',[15 60]);
m_coast('color','k');
m_states('k');
m_grid('linestyle','none');