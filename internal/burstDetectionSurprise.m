function experiment = burstDetectionSurprise(experiment, varargin)
% BURSTDETECTIONSURPRISE Adaptation of: https://doi.org/10.1016/j.jneumeth.2006.09.024
%
% USAGE:
%    experiment = burstDetectionSurprise(experiment, varargin)
%
% INPUT arguments:
%    experiment - experiment structure
%
% INPUT optional arguments ('key' followed by its value):
%    see: burstDetectionSurpriseOptions
%
% OUTPUT arguments:
%    experiment - experiment structure
%
% EXAMPLE:
%    experiment = burstDetectionSurprise(experiment)
%
% Copyright (C) 2016-2018, Javier G. Orlandi <javiergorlandi@gmail.com>

% EXPERIMENT PIPELINE
% name: surprise burst detection
% parentGroups: spikes: bursts
% optionsClass: burstDetectionSurpriseOptions
% requiredFields: spikes, ROI, folder, name

[params, var] = processFunctionStartup(burstDetectionSurpriseOptions, varargin{:});
% Define additional optional argument pairs
params.pbar = [];
params.verbose = true;
params = parse_pv_pairs(params, var);
params = barStartup(params, 'Detecting bursts', true);
%--------------------------------------------------------------------------

% Fix in case for some reason the group is a cell
if(iscell(params.group))
  mainGroup = params.group{1};
else
  mainGroup = params.group;
end
% Check if its a project or an experiment
switch params.saveOptions.saveBaseFolder
  case 'experiment'
    baseFolder = experiment.folder;
  case 'project'
    baseFolder = [experiment.folder '..' filesep];
  otherwise
    baseFolder = experiment.folder;
end


% Consistency checks
if(params.saveOptions.onlySaveFigure)
  params.saveOptions.saveFigure = true;
end
if(params.saveOptions.saveFigure)
  params.plotResults = true;
end
if(ischar(params.styleOptions.figureSize))
  params.styleOptions.figureSize = eval(params.styleOptions.figureSize);
end

% Create necessary folders
if(~exist(baseFolder, 'dir'))
  mkdir(baseFolder);
end
figFolder = [baseFolder 'figures' filesep];
if(~exist(figFolder, 'dir'))
  mkdir(figFolder);
end
exportFolder = [baseFolder 'exports' filesep];
if(~exist(exportFolder, 'dir'))
  mkdir(exportFolder);
end

% Get ALL subgroups in case of parents
if(strcmpi(mainGroup, 'all'))
  groupList = getExperimentGroupsNames(experiment);
else
  groupList = getExperimentGroupsNames(experiment, mainGroup);
end

% Some definitions
minBurstSeparation = params.minBurstSeparation;
minParticipators = params.minParticipators;

% Empty check
if(isempty(groupList))
  logMsg(sprintf('Group %s not found on experiment %s', mainGroup, experiment.name), 'w');
  return;
end

% Time to iterate through all the groups
for git = 1:length(groupList)
  if(params.pbar > 0)
    ncbar.setBarTitle(sprintf('Detecting bursts from group: %s', groupList{git}));
  end
  if(strcmpi(groupList{git}, 'none'))
    members = 1:length(experiment.ROI);
    groupName = 'everything';
    groupIdx = 1;
  else
    [members, groupName, groupIdx] = getExperimentGroupMembers(experiment, groupList{git});
  end
  
  %%% HACK
  if(strcmpi(params.surpriseMode, 'global'))
    maxN = min([length(members), 100]);
    members = members(randperm(length(members), maxN));
  end
  
  % Check for empty group
  if(isempty(members) && params.verbose)
    logMsg(sprintf('Found empty group: %s', groupList{git}), 'w');
    continue;
  end
  
  experiment.spikes = cellfun(@(x)x(:)', experiment.spikes, 'UniformOutput', false);
  
  ar=[cellfun(@(x)x, experiment.spikes(members), 'UniformOutput', false)];
  
  SpikeTimes = [];
  SpikeIdx = [];
  for it = 1:length(ar)
    if(~isnan(ar{it}))
      SpikeTimes = [SpikeTimes, ar{it}];
      SpikeIdx = [SpikeIdx, ones(size(ar{it}))*it];
    end
  end
  mat = [SpikeTimes', SpikeIdx'];
  ar = sortrows(mat, 1);
  SpikeTimes = ar(:,1)';
  %SpikeTimes = SpikeTimes +(rand(size(SpikeTimes))-0.5)/experiment.fps;
  
  SpikeIdx = members(ar(:,2))';
  firings.T = SpikeTimes;
  firings.N = SpikeIdx;
  sortedSpikeTimes = sort(SpikeTimes);
  [a, b] = hist(firings.N, 1:max(firings.N));
  [~, sortedChannels] = sort(a, 'ascend');
  sortedChannels = arrayfun(@(x)find(x==sortedChannels), 1:max(firings.N));
  if(params.reorderChannels)
    minC = min(sortedChannels(firings.N));
  else
    minC = 0;
  end
  
  %%% The surprise model
  RSalpha = -log(params.surpriseThreshold);
  limit = params.maximumISI;
  switch params.globalSurpriseThresholdType
    case 'relative'
      schmittHigh = ceil(params.globalSurpriseThresholds(1)*length(members));
      schmittLow = floor(params.globalSurpriseThresholds(2)*length(members));
    case 'absolute'
      schmittHigh = params.globalSurpriseThresholds(1);
      schmittLow = params.globalSurpriseThresholds(2);
  end
  switch params.surpriseMode
    case 'single'
      %[schmittHigh schmittLow]
      firingNeurons = unique(firings.N);
      surpriseListFrames = zeros(size(experiment.t));
      surprise.T = [];
      surprise.N = [];
      for it = 1:length(firingNeurons)
        valid = find(firings.N == firingNeurons(it));
        tn = firings.T(valid);
        ISI = diff(tn);
        if(~isempty(ISI))
          [archive_burst_RS,archive_burst_length,archive_burst_start]=burstSurprise(tn,limit,RSalpha);
          if(~isempty(archive_burst_start))
            for it2 = 1:length(archive_burst_start)
              validSpikes = archive_burst_start(it2):(archive_burst_start(it2)+archive_burst_length(it2)-1);
              surprise.T = [surprise.T, tn(validSpikes)];
              surprise.N = [surprise.N, ones(size(validSpikes))*firingNeurons(it)];
              surpriseFrames = round(min(tn(validSpikes))*experiment.fps):round(max(tn(validSpikes))*experiment.fps);
              invalid = find(surpriseFrames < 1 | surpriseFrames > length(experiment.t));
              surpriseFrames(invalid) = [];
              surpriseListFrames(surpriseFrames) = surpriseListFrames(surpriseFrames) + 1;
            end
          end
        end
      end
    case 'global'
      %schmittHigh = 0.1;
      %schmittLow = 0;
      surpriseListFrames = zeros(size(experiment.t));
      surprise.T = [];
      surprise.N = [];
      %tn = unique(firings.T);
      tn = firings.T;
      %tn = tn + (rand(size(tn))-0.5)/experiment.fps;
      ISI = diff(tn);
      if(~isempty(ISI))
        [archive_burst_RS,archive_burst_length,archive_burst_start]=burstSurprise(tn,limit,RSalpha);
        if(~isempty(archive_burst_start))
          for it2 = 1:length(archive_burst_start)
            validSpikes = archive_burst_start(it2):(archive_burst_start(it2)+archive_burst_length(it2)-1);
            surprise.T = [surprise.T, tn(validSpikes)];
            surprise.N = [surprise.N, ones(size(validSpikes))];
            surpriseFrames = round(min(tn(validSpikes))*experiment.fps):round(max(tn(validSpikes))*experiment.fps);
            invalid = find(surpriseFrames < 1 | surpriseFrames > length(experiment.t));
            surpriseFrames(invalid) = [];
            surpriseListFrames(surpriseFrames) = surpriseListFrames(surpriseFrames) + length(validSpikes);
          end
        end
      end
  end

  y = schmitt_trigger(surpriseListFrames, schmittLow, schmittHigh);

  avgTraceAbove = nan(size(surpriseListFrames));
  avgTraceAbove(find(y)) = surpriseListFrames(find(y));

  split = SplitVec(y, 'equal', 'first');
  splitVals = SplitVec(y, 'equal');
  validSplit = find(y(split) == 1);

  burstDuration = zeros(length(validSplit), 1);
  burstAmplitude = zeros(length(validSplit), 1);
  burstStart = zeros(length(validSplit), 1);
  burstFrames = cell(length(validSplit), 1);
  burstChannels = cell(length(validSplit), 1);
  for i = 1:length(validSplit)
    burstFrames{i} = split(validSplit(i)):(split(validSplit(i))+length(splitVals{validSplit(i)})-1);
    burstT = experiment.t(burstFrames{i});
    burstDuration(i) = max(burstT)-min(burstT);
    burstStart(i) = min(burstT);
    validSpikes = find(SpikeTimes >= burstStart(i) & SpikeTimes <= burstStart(i)+burstDuration(i));
    burstAmplitude(i) = length(validSpikes);
    burstChannels{i} = unique(SpikeIdx(validSpikes));
  end
  burstStructure = struct;
  burstStructure.duration = burstDuration;
  burstStructure.amplitude = burstAmplitude;
  burstStructure.start = burstStart;

  burstStructure.frames = burstFrames;
  burstStructure.participators = burstChannels;
  burstStructure.thresholds = [schmittLow, schmittHigh];
  burstStructure.N = [];

  if(length(burstStructure.start) > 1)
    burstStructure.IBI = burstStructure.start(2:end) - (burstStructure.start(1:end-1) + burstStructure.duration(1:end-1));
  else
    burstStructure.IBI = [];
  end

  detectedFullSchmitt = [];
  for i=1:length(burstStructure.start)
    detectedFullSchmitt = [detectedFullSchmitt burstStructure.start(i) burstStructure.start(i)+burstStructure.duration(i) NaN];
  end

  % Merge bursts between too short IBIs
  done = false;
  while(~done)
    done = true;
    for it = 1:length(burstStructure.IBI)
      % Remove burst it+1 and add it to burst it
      if(burstStructure.IBI(it) <= minBurstSeparation)
        done = false;
        burstStructure.duration(it) = burstStructure.start(it+1)+burstStructure.duration(it+1)-burstStructure.start(it);
        burstStructure.amplitude(it) = burstStructure.amplitude(it) + burstStructure.amplitude(it+1);
        burstStructure.frames{it} = burstStructure.frames{it}(1):burstStructure.frames{it+1}(end);
        burstStructure.participators{it} = unique([burstStructure.participators{it}, burstStructure.participators{it+1}]);
        % Now remove the next one
        burstStructure.duration(it+1) = [];
        burstStructure.amplitude(it+1) = [];
        burstStructure.start(it+1) = [];
        burstStructure.frames(it+1) = [];
        burstStructure.participators(it+1) = [];
        % Recompute IBIs
        if(length(burstStructure.start) > 1)
          burstStructure.IBI = burstStructure.start(2:end)- (burstStructure.start(1:end-1) + burstStructure.duration(1:end-1));
        else
          burstStructure.IBI = [];
        end
        break;
      end
    end
  end

  invalidBursts = find(cellfun(@length,burstStructure.participators) < minParticipators);
  burstStructure.duration(invalidBursts) = [];
  burstStructure.amplitude(invalidBursts) = [];
  burstStructure.start(invalidBursts) = [];
  burstStructure.frames(invalidBursts) = [];
  burstStructure.participators(invalidBursts) = [];
  burstStructure.invalidBursts = length(invalidBursts);
  if(length(burstStructure.start) > 1)
    burstStructure.IBI = burstStructure.start(2:end)- (burstStructure.start(1:end-1) + burstStructure.duration(1:end-1));
  else
    burstStructure.IBI = [];
  end
  
  if(params.plotResults)
    if(~params.reorderChannels)
      sortedChannels = 1:max(firings.N);
    end

    figName = sprintf('Surprise bursts %s', experiment.name);
    if(params.saveOptions.onlySaveFigure)
      figVisible = 'off';
    else
      figVisible = 'on';
    end
    figureHandle = figure('Name', figName, 'NumberTitle', 'off', 'Visible', figVisible, 'Tag', 'netcalPlot');
    figureHandle.Position = setFigurePosition(gcf, 'width', params.styleOptions.figureSize(1), 'height', params.styleOptions.figureSize(2));
      
    a2 = subplot(3, 1, 2);
    hold on;
    plot(firings.T, sortedChannels(firings.N)-minC, 'k.');
    detected = [];
    for i=1:length(burstStructure.start)
      %Detected = [ Detected Burst.T_start(i) Burst.T_end(i) NaN ];
      valid = find(firings.T >= burstStructure.start(i) & firings.T <= (burstStructure.start(i)+burstStructure.duration(i)));

      plot(firings.T(valid), sortedChannels(firings.N(valid))-minC, '.');
      detected = [detected burstStructure.start(i) burstStructure.start(i)+burstStructure.duration(i) NaN];
    end
    % Now plot the surprises
    %for it = 1:length(surprise.T)
    %plot(surprise.T, sortedChannels(surprise.N)-minC, 'or', 'MarkerSize', 8);
    %a1.ColorOrderIndex = 1;
    if(strcmpi(params.surpriseMode, 'single'))
      plot(surprise.T, sortedChannels(surprise.N)-minC, 'b.');
    else
      plot(surprise.T, surprise.N*(max(sortedChannels)-minC+2), 'b.');
    end
    %end
    linesMap = lines(2);
    plot(detectedFullSchmitt, ones(size(detectedFullSchmitt))*max(sortedChannels(firings.N))-minC+5, 'v-', 'MarkerSize', 6, 'LineWidth', 2, 'Color', linesMap(2,:), 'MarkerFaceColor', linesMap(2,:))
    plot(detected, ones(size(detected))*max(sortedChannels(firings.N))-minC+5, 'v-', 'MarkerSize', 6, 'LineWidth', 2, 'Color', linesMap(1,:), 'MarkerFaceColor', linesMap(1,:))

    xlabel('time (s)')
    ylabel('sorted ROI');

    box on;
    title(sprintf('Raster plot - N: %d', length(burstStructure.amplitude)));
    xl = xlim;

    a3 = subplot(3, 1, 3);
    hold on;
    try
      experiment = loadTraces(experiment, 'smoothed');
      plot(experiment.t, mean(experiment.traces(:, members), 2),'Color',[1 1 1]*0.75);
      ax = gca;
      ax.ColorOrderIndex = 1;
      for i=1:length(burstStructure.start)
        valid = find(experiment.t >= burstStructure.start(i) & experiment.t <= (burstStructure.start(i)+burstStructure.duration(i)));
        plot(experiment.t(valid), mean(experiment.traces(valid, members), 2));
      end
      xlim([min(experiment.t) max(experiment.t)]);
    catch
    end
    title('Average trace');
    xlabel('time (s)');
    ylabel('DF/F');
    box on;

    a1 = subplot(3, 1, 1);
    plot(experiment.t, surpriseListFrames);
    hold on;
    xlim([min(experiment.t) max(experiment.t)]);
    xl = xlim;
    plot(xl, [1,1]*schmittLow);
    plot(xl, [1,1]*schmittHigh);
    %legend('ISI_N','low','high');
    title(['Surprise Schmitt trigger detection: ' experiment.name]);
    xlabel('time (s)');
    ylabel('Simultaneous Surprise bursts');
    box on;
    linkaxes([a1 a2 a3], 'x');
    xlim([min(experiment.t) max(experiment.t)]);
    
    ui = uimenu(figureHandle, 'Label', 'Export');
    uimenu(ui, 'Label', 'Figure',  'Callback', {@exportFigCallback, {'*.pdf';'*.eps'; '*.tiff'; '*.png'}, strrep([figFolder, figName], ' - ', '_'), params.saveOptions.saveFigureResolution});
      
    if(params.saveOptions.saveFigure)
      if(~isempty(params.saveOptions.saveFigureTag))
        figName = [figName params.saveOptions.saveFigureTag];
      end
      export_fig([figFolder, figName, '.', params.saveOptions.saveFigureType], ...
                  sprintf('-r%d', params.saveOptions.saveFigureResolution), ...
                  sprintf('-q%d', params.saveOptions.saveFigureQuality), figureHandle);
    end
    if(params.saveOptions.onlySaveFigure)
     close(figureHandle);
    end
    if(~isempty(params.styleOptions.figureTitle))
      mtit(params.styleOptions.figureTitle);
    end
  end
  % Store results
  
  burstList = burstStructure;
  
  experiment.spikeBursts.(groupName){groupIdx} = burstList;

  logMsg(sprintf('%d bursts detected on group %s in %s', length(burstList.start), groupList{git}, experiment.name));
  logMsg(sprintf('%.2f s mean duration', mean(burstList.duration)));
  logMsg(sprintf('%.2f mean maximum amplitude', mean(burstList.amplitude)));
  logMsg(sprintf('%.2f s mean IBI', mean(burstList.IBI)));
end

%--------------------------------------------------------------------------
barCleanup(params);
%--------------------------------------------------------------------------

end