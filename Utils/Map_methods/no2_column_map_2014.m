function [cbhandle, GriddedColumn, longrid, latgrid, GriddedCount, parsed_vars] = no2_column_map_2014( start_date_in, end_date_in, lon_bdy, lat_bdy, varargin )
%NO2 Map Function - Uses the m_map package to draw maps of NO2 column density over the US (primarily). Returns the colorbar handle. Arguments:
% Returns: colorbar handle, no2 grid, lon grid, lat grid.
% REQUIRED:
%   start_date = a string in yyyy/mm/dd format that represents the starting
%      date of the period to average over. If you want to average multiple,
%      noncontinguous periods, enter a cell array with the start dates for
%      each period.
%   end_date = has the same format and structure as startdate, but is the
%      ending dates of the time period(s)
%   lon_bdy = a 1x2 matrix with the longitude boundaries
%   lat_bdy = a 1x2 matrix with the latitude boundaries
%
% PARAMETER VALUES:
%   mapfield = the field in the OMI data structure that will be mapped.
%       Defaults to BEHRColumnAmountNO2Trop, must be a string.  Changing
%       this value will not change any of the accept/reject pixel
%       parameters, any that use the BEHR NO2 column will still use that
%       value.
%   resolution = the size of the lat/lon boxes in degrees. Defaults to 0.05
%   projection = 'conic' or 'mercator'. Conic uses Albers Equal-Area Conic,
%       mercator uses (surprise) a mercator projection. Conic is default.
%   coast = which coastline to use. Options are: 'full', 'high',
%       'medium'/'intermediate', 'low', 'crude', 'default'.  Defaults to
%       default (duh) which uses the regular m_coast; the others use m_gshhs
%   color = the color to plot the coast and state boundaries, Defaults to
%       white.
%   cbrange = a 1x2 matrix with range of values for the colorbar.  By
%       default, this will be set by MATLAB.
%   states = Set to 0 to avoid plotting US state boundaries.
%   behrdir = The directory where BEHR files can be found.
%   fileprefix = 'OMI_BEHR_VSTR_', where VSTR is replaced with the current
%       version string defined by BEHR_version  by default. In general, this is
%       the part of the .mat filenames before the date.
%   flags = a cell array of flags that change the behavior of the function:
%         'weekend'/'weekday' --> only average over weekend or weekdays respectively
%         'r_weekend'/'r_weekday' --> average over Su only or Tu-F only
%         'US_holidays' --> Use normal US holidays (defined by isbusdays
%                function). Otherwise, defaults to no holidays.
%   clouds = Use OMI cloud fraction (default) or MODIS cloud fraction
%       ('modis').
%   cloudfraccrit = The maximum allowable cloud fraction. Defaults to 0.2
%       for OMI and 0 for MODIS 
%   rowanomaly = Parse mode for row anomaly
%       (see function "omi_rowanomaly"). Default value is 'XTrackFlags',
%       other options are 'AlwaysByRow', 'RowsByTime', and
%       'XTrackFlagsLight'.
%   rows = restrict the averaging to using certain rows. This is useful to
%       duplicate Luke's check where he averaged a month's worth of data
%       from each side of the detector and found a significant difference
%       in the average, indicating that there was a bias in the viewing
%       angle dependence. Input should be a 1x2 vector that gives the min
%       and max row. Remember row indicies are 0 based, and go from 0 to
%       59.
%   sza = maximum allowed solar zenith angle to use, in degrees. Defaults to
%       180, i.e. all angles will be used.  
%   makefig = true or false; whether to make a figure or not. Defaults to
%       true. Errors if set to false but only 1 output requested, as this
%       means that the NO2 column data would not be saved.
%
%   Josh Laughner <joshlaugh5@gmail.com> 25 Apr 2014

p = inputParser;
p.addParameter('mapfield','BEHRColumnAmountNO2Trop',@isstr)
p.addParameter('behrdir','/Volumes/share-sat/SAT/BEHR/BEHR_Files_2014',@(x) exist(x,'dir'))
p.addParameter('resolution',0.05,@isscalar);
p.addParameter('projection','conic',@(x) any(strcmpi(x,{'conic','mercator'}))); %Ensure that the projection type will be recognized
p.addParameter('coast','default',@(x) any(strcmpi(x,{'default','high','intermediate','medium','low','crude','default'})));
p.addParameter('color','w');
p.addParameter('cbrange',[],@(x) length(x) == 2);
p.addParameter('states',1,@isscalar);
p.addParameter('fileprefix',sprintf('OMI_BEHR_%s_',BEHR_version),@isstr);
p.addParameter('flags',{},@iscell);
p.addParameter('clouds','omi',@isstr);
p.addParameter('cloudfraccrit',-1,@isscalar)
p.addParameter('rowanomaly','XTrackFlags',@(x) any(strcmpi(x,{'AlwaysByRow','RowsByTime','XTrackFlags','XTrackFlagsLight'}))) %Ensure that the rowanomaly value is one of the allowed 4
p.addParameter('rows',[],@(x) (isnumeric(x) && (numel(x) == 0 || numel(x) == 2)));
p.addParameter('sza',180,@(x) (isnumeric(x) && isscalar(x) && x >= 0))
p.addParameter('makefig', true, @(x) (isscalar(x) && (isnumeric(x) || islogical(x))));

p.parse(varargin{:});
parsed_vars = p.Results;
mapfield = parsed_vars.mapfield;
behr_dir = parsed_vars.behrdir;

%****************************%
% CONSOLE OUTPUT LEVEL - 0 = none, 1 = minimal, 2 = all messages, 3 = times %
% Allows for quick control over the amount of output to the console.
% Choose a higher level to keep track of what the script is doing.
DEBUG_LEVEL = 2;
%****************************%

E = JLLErrors;
if ~parsed_vars.makefig && nargout < 2
    E.badinput('makefig is false, but the NO2 column output has no variable to go to. Additional outputs required.');
end

%****************************%
%       FLAG PARSING         %
%****************************%

if any(strcmpi('US_holidays',parsed_vars.flags))
    holidays = [];
else
    holidays = 0;
end

% Sets to 1 if flags for 'weekend' or 'weekday' are present
week_bool = zeros(1,5); week_bool(5) = 1; %Default to all days
week_bool(1) = any(strcmpi('weekend',parsed_vars.flags));
week_bool(2) = any(strcmpi('weekday',parsed_vars.flags));
week_bool(3) = any(strcmpi('r_weekend',parsed_vars.flags));
week_bool(4) = any(strcmpi('r_weekday',parsed_vars.flags));

if sum(week_bool(1:4))>1; error('NO2ColMap:DayOfWeek','More than one day-of-week flag set'); end

wksetting_cell = {'Weekend (Sa-Su)','Weekdays (M-F)','Restricted Weekend (Sun only)','Restricted Weekdays (Tu-F)','All Days'};
if DEBUG_LEVEL > 1; fprintf('week_bool = %s\n',mat2str(week_bool)); end

week_setting = find(week_bool,1,'first');
if DEBUG_LEVEL > 1; fprintf('week_setting = %s: %s\n', mat2str(week_setting),wksetting_cell{week_setting}); end
switch week_setting
    case 1 %Find normal weekend days, so set "weekend" to "weekdays" so that isbusday returns true for Sat and Sun
        weekend = [0 1 1 1 1 1 0];
    case 2 %Set up to find normal weekdays
        weekend = [1 0 0 0 0 0 1];
    case 3 %Set up to find Sundays only (restricted weekend, avoids "overflow" emisions from Fri --> Sat)
        weekend = [0 1 1 1 1 1 1];
    case 4 %Set up to find Tu-F, avoiding lower rollover emissions from Su --> M
        weekend = [1 1 0 0 0 0 1];
    otherwise %If no weekend argument passed, use all days of week
        weekend = [0 0 0 0 0 0 0];
end

%****************************%
%  PARSE START AND END DATES %
%****************************%

if ~iscell(start_date_in) && ~iscell(end_date_in); start_date{1} = start_date_in; end_date{1} = end_date_in;
elseif iscell(start_date_in) && iscell(end_date_in); start_date = start_date_in; end_date = end_date_in;
else error('NO2ColMap:date_ranges','Start and end dates must both be cell arrays or both not be cell arrays');
end


%****************************%
%    LATITUDE & LONGITUDE    %
%****************************%
if lat_bdy(1) > lat_bdy(2); error('NO2ColMap:lat_bdy','Latitude minimum is greater than latitude maximum.'); end
if lon_bdy(1) > lon_bdy(2); error('NO2ColMap:lon_bdy','Longitude minimum is greater than longitude maximum.'); end

res = parsed_vars.resolution;
lats = lat_bdy(1):res:lat_bdy(2);
lons = lon_bdy(1):res:lon_bdy(2);

[longrid, latgrid] = meshgrid(lons,lats);

%****************************%
%      CLOUD FRACTION        %
%****************************%
cloud_type = parsed_vars.clouds;
cloud_frac = parsed_vars.cloudfraccrit;
if strcmpi(cloud_type,'omi') && cloud_frac < 0
    cloud_frac = 0.2; %Set the cloud fraction criteria to 20% unscaled if OMI clouds used and no other value given
elseif strcmpi(cloud_type,'modis') && cloud_frac < 0
    cloud_frac = 0;
elseif strcmpi(cloud_type,'rad') && cloud_frac < 0
    cloud_frac = 0.5;
elseif strcmpi(cloud_type, 'omi') || strcmpi(cloud_type, 'modis') || strcmpi(cloud_type, 'rad') %Check that the cloud type is recognized, if the value of cloud_frac is valid
else
    error('no2_col_map:cloud_type','Cloud type must be "OMI", "MODIS", or "RAD"')
end

if cloud_frac < 0 || cloud_frac > 1
    error('no2_col_map:cloud_frac','Cloud fraction criterion must be between 0 and 1')
end

%Add the 'Utils' folder and all subfolders to MATLAB's search path. Within
%the Git repository for BEHR, this is the /Utils folder. This includes the
%m_map package.
addpath(genpath('/Users/Josh/Documents/MATLAB/BEHR/Utils'))


%****************************%
%       MAIN LOOP            %
%****************************%

per = length(start_date);
first_time_through = 1; % A flag to run any scripts required on the first time through the loop.
if per ~= length(end_date); error('NO2ColMap:TimePeriods','no2_column_map - startdate and enddate are unequal lengths'); end

for period = 1:per %Loop over each temporal period you wish to average
    startdate = start_date{period}; enddate = end_date{period};
    for a = datenum(startdate):datenum(enddate)
        date = datestr(a,29); %Convert the current date number to a string in the format yyyy-mm-dd
        year = date(1:4);
        month = date(6:7);
        day = date(9:10);
        
        if DEBUG_LEVEL > 0; fprintf(' Now on %s\n',date); end
        
        filepath = behr_dir;
        filename = [parsed_vars.fileprefix,year,month,day,'.mat'];
        file = fullfile(filepath,filename);
        
        if exist(file,'file') ~= 2; fprintf(' %s not found\n',filename);
        elseif ~isbusday(date,holidays,weekend) % Tests if the day is a weekend based on the weekend flags set and whether or not to use US holidays.
            if DEBUG_LEVEL > 1; fprintf('\t %s will not be considered for averaging\n',date); end
        else
            O=load(file,'OMI');
            if isempty(O.OMI)
                warning('No gridded data found in %s, skipping', file);
                continue
            else
                OMI = O.OMI;
            end
            
            if first_time_through %The first time through, generate the Sum matrices that will hold the total areaweight and weighted column density
                if DEBUG_LEVEL > 0; fprintf('Initializing SumWeightedColumn and SumWeight matrices\n'); end
                SumWeightedColumn = zeros(size(OMI(1).(mapfield)));
                SumWeight = zeros(size(OMI(1).(mapfield)));
                Count = zeros(size(OMI(1).(mapfield)));
                omilats = OMI(1).Latitude;
                omilons = OMI(1).Longitude;
                
                if isfield(OMI,'BEHRColumnAmountNO2Trop'); useBEHR = 1;
                else useBEHR = 0; fprintf('File is not a BEHR file, using OMI SP settings\n');
                end
                first_time_through = 0; % Don't run this section again.
            end
            
           
            for s=1:numel(OMI) 
                if any(OMI(s).Latitude ~= omilats | OMI(s).Longitude ~= omilons)
                    error('NO2ColMap:OMILatLons','OMI Lat and Lons for %s, swath %u do not agree with previous lat/lon matrices',date,s);
                end
            end
            
            [this_WeightedColumn, this_Weight, this_Count] = BEHR_day_no2(OMI,'mapfield', mapfield, 'cloud_prod', cloud_type, 'cloud_frac_max', cloud_frac, 'row_anomaly', parsed_vars.rowanomaly, 'rows', parsed_vars.rows, 'sza', parsed_vars.sza);
            SumWeightedColumn = SumWeightedColumn + this_WeightedColumn;
            SumWeight = SumWeight + this_Weight;
            Count = Count + this_Count;
               
        end %End if statement checking if the BEHR file for the current day exists
    end %End the loop over all days in this time period
end %End the loop over all time periods

% Normalize the areaweight for each pixel to 1.
ColumnData = SumWeightedColumn ./ SumWeight;

% Grid the data. 
nans = find(isnan(ColumnData));
ColumnData(nans) = []; omilats(nans) = []; omilons(nans) = []; Count(nans) = [];
GriddedColumn = griddata(omilons,omilats,ColumnData,longrid,latgrid);
GriddedCount = griddata(omilons,omilats,Count,longrid,latgrid);

if parsed_vars.makefig
    % Open a new figure.
    figure;
    
    % Prepare the map
    if strcmpi('conic',parsed_vars.projection)
        m_proj('Albers Equal-Area Conic', 'lon', lon_bdy, 'lat', lat_bdy);
    elseif strcmpi('mercator', parsed_vars.projection)
        m_proj('Mercator', 'long', lon_bdy, 'lat', lat_bdy);
    end
    
    % Map the NO2 concentrations
    m_pcolor(longrid, latgrid, GriddedColumn); shading('flat');
    
    % Draw the coast
    switch parsed_vars.coast
        case 'full'
            m_gshhs_f('color',parsed_vars.color);
        case 'high'
            m_gshhs_h('color',parsed_vars.color);
        case {'intermediate', 'medium'}
            m_gshhs_i('color',parsed_vars.color);
        case 'low'
            m_gshhs_l('color',parsed_vars.color);
        case 'crude'
            m_gshhs_c('color',parsed_vars.color);
        otherwise
            m_coast('color',parsed_vars.color);
    end
    
    % Draw the states, as long as their drawing is not overridden
    if parsed_vars.states; m_states('w'); end
    
    % Add the lat lon grid with no lines to fix the appearance of the map
    m_grid('linestyle','none');
    
    cbhandle = colorbar;
    if ~isempty(parsed_vars.cbrange); caxis(parsed_vars.cbrange); end
else
    cbhandle = nan;
end

end %end function

