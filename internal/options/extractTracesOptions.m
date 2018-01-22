classdef extractTracesOptions < baseOptions
% EXTRACTTRACESOPTIONS Options for extract traces
%   Class containing the possible ways to extract the traces
%
%   Copyright (C) 2016, Javier G. Orlandi <javierorlandi@javierorlandi.com>
%
%   See also extractTraces, baseOptions, optionsWIndow

  properties
    % Choose what movie to preprocess (standard or denoised)
    movieToPreprocess = {'standard', 'denoised'};
    
    %If not empty, only analyzes the frames between initial and final (in seconds)
    subset = [0 600];

     % How to perform the average for each ROI:
     % - 'mean' - uses the mean of each ROI fluorescence
     % - 'median' - uses the median of each ROI fluorescence
    averageType = {'mean', 'median'};
  end
  methods 
    function obj = setExperimentDefaults(obj, experiment)
      if(~isempty(experiment) && isstruct(experiment))
        try
          %obj.subset = [0 round(experiment.totalTime)];
          obj.subset = [0 experiment.totalTime];
        catch ME
            logMsg(strrep(getReport(ME), sprintf('\n'), '<br/>'), 'e');
        end
      end
    end
  end
end