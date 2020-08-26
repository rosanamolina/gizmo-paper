function summarizeScans(plotFigures, saveData, evolutionRoundSummaryLocation, plateName, plateDirectory)
%{
summarizeScans.m Summarizes the '.dat' scan data in the working directory
and finds the top ~5 brightest colonies.
Inputs: 
    plotFigures : Boolean of whether or not to plot figures (if you do
        not plot figures then they will not be saved)
    saveData : Boolean of whether or not to save data (figures, etc.)
    evolutionRoundSummaryLocation : (optional) filename (including path) of
        where to append the plate results. It is a .csv to contain
        results from all the plates in one round of evolution.
    plateName : (optional) Name of the scanned plate. If this is not
        provided, the plateName will be the grandparent folder name
    plateDirectory : (optional) Folder name (including path) of where to
        save data specific to this plate. 
Outputs:
    None.
Plots the following figures:
    1. Line plot of the top colony scans (reduced by averaging 500 points)
    2. Histogram of the max intensities of the plate
    3. Scatter plot of the max intensities of the plate
Saves the following files:
    1. .png files of above gfigures (if plotted)
    2. .mat file containing structure with reduced scans and max values for
       each colony
    3. .txt file containing plate summary
    4. (if provided evolutionRoundSummaryLocation) .csv file meant to 
       contain results from all the plates in one round of evolution.
%}

% Set the number to reduce the scan data by (to minimize storage size and 
% for viewing purposes only!)
N=500; 

% Get all .dat files in the working directory
scanDirectory = pwd;
files=dir([scanDirectory '/*.dat']);
if isempty(files)
    error('Go to the folder with the .dat scan data.');
end

nColonies = length(files);

folderDividers = strfind(scanDirectory,'/'); % For Mac
if isempty(folderDividers)
    folderDividers = strfind(scanDirectory,'\'); % For Windows
end

if ~exist('plateName','var')
    % Get the plate name based on the name of the grandparent folder
    plateName = scanDirectory(folderDividers(end-2)+1:folderDividers(end-1)-1);
end

if ~exist('plateDirectory', 'var')
    % Log figures, etc. into the grandfather folder
    plateDirectory = scanDirectory(1:folderDividers(end-1)-1);
end

% Print plateName to command window to keep track of which plate was analyzed
fprintf('% s\n',plateName);

% Clean up plateName for the filename
plateFilename = strrep(plateName, '/', '-');
plateFilename = strrep(plateFilename, ' ', '_');

% Create structure analyzedScans, length nColonies with 2 fields:
% 'Short' - colony scan data, shortened by N for storage and visualization
% 'Max' - maximum value of colony scans that were good, or 0 for those that
% were bad (i.e., the scan depth did not capture the maximum value).
analyzedScans = struct('Short',cell(1,nColonies),'Max',[]);
for i = 1:nColonies
    scan = loadColony(files(i).name);
    [good, scanSubBkgd] = checkScan(scan); % subtracts bkgd and checks if z is good
    analyzedScans(i).Short = reduceByMean(scanSubBkgd,N);
    if good
        analyzedScans(i).Max = max(scanSubBkgd);
    else
        analyzedScans(i).Max = 0; % Indicates that it did not pass checkScan
    end
end

% Get the maximum values of the 'good' colonies
goodMax = [analyzedScans([analyzedScans.Max]~=0).Max];

% Get the top (i.e. brightest) colonies
[topMax, topIds, nTopColonies] = getTop();

% Plot figures
if plotFigures
    figScatter = plotMaxScatter();
    figHistogram = plotMaxHist();
    figTop = plotTop();
end

% Save files
if saveData
    
    % Store plate results
    nGoodColonies = length(goodMax);
    fractionGood = nGoodColonies/nColonies;
    meanGoodMax = mean(goodMax);
    covGoodMax = std(goodMax)/meanGoodMax * 100;
    
    % Save the analyzedScans structure
    save([plateDirectory '/' plateFilename '.mat'], 'analyzedScans');
    
    % Save figures if they were plotted
    if plotFigures
        % Save the figures as '.png' files
        ending = [plateFilename '.png'];
        saveas(figTop, [plateDirectory '/top_' ending]);
        saveas(figScatter, [plateDirectory '/scatter_' ending]);
        saveas(figHistogram, [plateDirectory '/histogram_' ending]);
    end
    
    % Save plate summary as .txt file
    savePlateSummary();
    
    % Append to evolution round summary file if
    % evolutionRoundSummaryLocation was provided
    if exist('evolutionRoundSummaryLocation', 'var')
        appendEvolutionRoundSummary()
    end
    
end


% Helper functions


    function [topFound, scanSubBkgd] = checkScan(scan)
        % Adapted from 'detectZ' function from NorthernLights.
        % Checks if the scan is good and subtracts the background.
        
        LOW_THRESHOLD = 10;
        
        % Subtract the minimum as a first step
        scanSubBkgd = scan - min(scan);
        
        % Filter data
        filteredData = filter((5000/numel(scanSubBkgd)), [1 (5000/numel(scanSubBkgd))-1], scanSubBkgd);
        
        % if data is too low we can safely assume this is
        % noise, i.e. missed colony.
        if max(filteredData) < LOW_THRESHOLD
            topFound = false;
        else
            % Auto detect the noise floor with the root mean square and set as a threshold
            threshold = sqrt(1/numel(filteredData).*(sum(filteredData.^2)));
            
            % Get all the values above that noise floor, if colony
            % is detected it should register as a large spike in
            % the line scan data.
            valsAboveThreshold = find(filteredData >= threshold);
            
            % Find the start and end of the spike, this roughly
            % determines the position of the colony in the 400um
            % spiral scan ranges
            
            start = valsAboveThreshold(1);
            stop = valsAboveThreshold(end);
            
            % Binarization
            data = filteredData;
            data(start:stop) = 1;
            data(1:start-1) = 0;
            data(stop+1:end) = 0;
            
            % Edge find
            top = max(diff(data));
            
            % The top of the colony should be the transition from 0
            % to 1.
            if (~isempty(top) && top == 1)
                % Check if the top is a false positive
                topIdx = find(diff(data) == 1);
                topPosition = topIdx/numel(filteredData);
                % The top is detected too close to the start or end of the stack.
                % It is likely a false positive.
                if topPosition <= 0.10 || topPosition >= 0.90
                    topFound = false;
                    % There is a leading spike from 0 to 1 and it is not
                    % near enough to the edges that it might be a false
                    % positive, assume it is good.
                else
                    topFound = true;
                end
            else
                topFound = false;  % Could not accurately identify a top
            end
            % Subtract background
            if topPosition >= .50
                % Subtract mean of values from start of scan
                scanSubBkgd = scan-mean(scan(2500:7500));
            else
                % Subtract mean of values from end of scan
                scanSubBkgd = scan-mean(scan(95000:99000));
            end
        end
    end


    function [topMax, topIds, nTopColonies] = getTop()
        % Find either the top 0.5% colonies or 5 colonies, whichever is greater
        nTopColonies = max([ceil(0.005*nColonies), 5]);
        % Sort the max values in descending order
        sortedMax = sortrows([1:nColonies; [analyzedScans.Max]]', 2, 'descend');
        % Split into two vectors containing the ids and max values of top colonies
        topIds = sortedMax(1:nTopColonies, 1);
        topMax = round(sortedMax(1:nTopColonies, 2));
    end


    function scan = loadColony(filename)
        fid = fopen(filename,'r');
        scan = fread(fid,'int16');
        fclose(fid);
    end


    function m = reduceByMean(vector, N)
        % Given a column vector, reduce the rows by the mean of N rows.
        vectorReshaped = reshape(vector(1:end - mod(numel(vector), N)), N, []);
        m = mean(vectorReshaped, 1)';
    end


% Plotting functions

    function figTop = plotTop()
        % Plots the shortened scan data of the top colonies, for visually
        % checking that the scan was good.
        figTop = figure; hold on;
        plot([analyzedScans(topIds).Short],'LineWidth',1.5);
        leg = cell(1,nTopColonies);
        for iColony = 1:nTopColonies
            leg{iColony} = ['#' num2str(topIds(iColony)) ', max ' num2str(topMax(iColony))];
        end
        legend('show', leg, 'color', 'none', 'Box', 'off');
        title(['Top colonies of ' plateName], 'Interpreter', 'none');
        ylabel('Intensity (a.u.)');
    end


    function figScatter = plotMaxScatter()
        % Makes a scatter plot of the max intensity values of the
        % colonies in the 'analyzedScans' structure from summarizeColonies.
        % The 'good' colonies are plotted as blue circles, while the 'bad'
        % colonies are plotted as red dots on the x axis b/c max was set to 0
        maxData = [analyzedScans.Max]';
        figScatter = figure; hold on;
        goodIds = find(maxData ~= 0);
        badIds = find(maxData == 0);
        plot(goodIds, maxData(goodIds), 'o');
        plot(badIds, maxData(badIds), '.', 'Color', 'r');
        ylabel('Max Intensity (a.u.)');
        xlabel('Colony ID');
        title(plateName, 'Interpreter', 'none');
    end


    function figHistogram = plotMaxHist()
        figHistogram = figure;
        histogram(goodMax);
        title(plateName, 'Interpreter', 'none');
        xlabel('Max Intensity (a.u.)'); ylabel('Count');
    end


% Saving functions

    function savePlateSummary()
        % Save the results of the plate in a .txt file in the
        % plateDirectory
        filename = [plateDirectory '/' plateFilename '.txt'];
        fid = fopen(filename, 'wt'); % write text.
        fprintf(fid, 'Summary of %s\n-----------------\n', plateName);
        fprintf(fid, 'Total colonies: %d\nGood colonies: %d\nGood/Total: %.2f\n',...
            nColonies, nGoodColonies, fractionGood);
        fprintf(fid, 'Max intensity values: mean = %.2f +/- %.2f%%\n', meanGoodMax, covGoodMax);
        for iColony = 1:nTopColonies
            fprintf(fid, 'Top colony %.0f of %.0f, id: %.0f, max intensity: %.0f \n',...
                iColony, nTopColonies, topIds(iColony), topMax(iColony));
        end
        fprintf(fid, '% s\n', ['Top colony ids: ', sprintf('% d, ',...
            topIds(1:end-1)), sprintf('% d', topIds(end))]);
        fclose(fid);
    end


    function appendEvolutionRoundSummary()
        % Append the results of the plate to a .csv file containing all of
        % the plates from the current round of evolution
        
        %Make sure it includes .csv
        if ~strcmp(evolutionRoundSummaryLocation(end-3:end),'.csv')
            filename = [evolutionRoundSummaryLocation '.csv'];
        else
            filename = evolutionRoundSummaryLocation;
        end
        
        fid = fopen(filename, 'at'); % append text
        fileinfo = dir(filename);
        % If nothing has been logged in this file yet, add column titles
        if fileinfo.bytes == 0
            fprintf(fid, ['Plate,Total Colonies,Good Colonies,Good/Total,'...
                'Mean Max Intensity, Relative SD of Max Intensity (%%),'...
                'Top Colony Intensities, Top Colony IDs,']);
        end
        
        % Fill in plate info
        fprintf(fid, '\n% s,% d,% d,%.2f,%.2f,%.2f,%.0f,',...
            plateName, nColonies, nGoodColonies, fractionGood,...
            meanGoodMax, covGoodMax);
        % Fill in top colony intensities and IDs
        fprintf(fid, '"% s","% s"', ...
            [sprintf('%.0f, ', topMax(1:end-1)), sprintf('%.0f', topMax(end))],...
            [sprintf('% d, ', topIds(1:end-1)), sprintf('% d', topIds(end))]);
        fclose(fid);
    end

end