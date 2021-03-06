function [loglik,Incr,retcode,Filters]=msre_linear_filter(syst,data_info,state_trend,SS,risk,options)
% H1 line
%
% Syntax
% -------
% ::
%
% Inputs
% -------
%
% Outputs
% --------
%
% More About
% ------------
%
% Examples
% ---------
%
% See also: 

% all rows of Q should sum to 1
% 0: no filters,
% 1: filtering,
% 2: filtering+updating,
% 3: filtering+updating+smoothing
% this decides the initial condition for both the state and the markov chain distributions in the
% the kalman filter.
% now add the defaults for the initialization process
if nargin==0
    if nargout>1
        error([mfilename,':: with no input argument, the number of output arguments cannot exceed 1'])
    end
    filt_options=struct('kf_algorithm','lwz',...%     alternative is kn (Kim and Nelson)
        'kf_tol',1e-20,...
        'kf_filtering_level',3,...
        'kf_riccati_tol',1e-6,...
        'kf_nsteps',1);
    init_options=kalman_initialization();
    defaults=utils.miscellaneous.mergestructures(filt_options,init_options);
    loglik=defaults;
    return
end


% apply the presample to the data
%--------------------------------
data_info.include_in_likelihood(1:options.kf_presample)=false;

% Trim the system matrices if possible
%---------------------------------------
minimum_state_for_estimation()

[init,retcode]=kalman_initialization(syst.T,syst.R,SS,risk,syst.Qfunc,options);

if retcode
    loglik=[];
    Incr=[];
    Filters=[];
else
    if data_info.npages>1
        [loglik,Incr,retcode,Filters]=msre_kalman_cell_real_time(syst,data_info,state_trend,init,options);
    else
        [loglik,Incr,retcode,Filters]=msre_kalman_cell(syst,data_info,state_trend,init,options);
    end
end
if isempty(loglik)
    loglik=nan;
end

    function minimum_state_for_estimation()
        % this function reduces the state size to accelerate estimation
        % it returns the indices of the union of state variables and observable
        % ones
    
        if options.kf_filtering_level==0 
            tmp=syst.T;
            h=numel(tmp);
            % The step below is critical for speed, though it may add some noise
            % when computing the filters for all the endogenous variables
            state=syst.forced_state|any(abs(tmp{1})>1e-9,1);
            for ii=2:h
                state=state | any(abs(tmp{ii})>1e-9,1);
            end
            n=numel(state);
            state(data_info.varobs_id)=true;
            
            % start compressing
            %--------------------
            data_info.varobs_id=game_old_positions(data_info.varobs_id);
            if isfield(data_info,'restr_y_id')
                data_info.restr_y_id=game_old_positions(data_info.restr_y_id);
            end
            for istate=1:h
                SS{istate}=SS{istate}(state);
                risk{istate}=risk{istate}(state);
                syst.T{istate}=syst.T{istate}(state,state);
                syst.R{istate}=syst.R{istate}(state,:,:);
                if ~isempty(state_trend{1})
                    state_trend{istate}=state_trend{istate}(state,:,:);
                end
            end
            syst.Qfunc=@(x)syst.Qfunc(re_inflator(x,state));
        end
        function newpos=game_old_positions(oldpos)
            newpos=false(1,n);
            newpos(oldpos)=true;
            newpos(~state)=[];
            newpos=find(newpos);
            [~,tags]=sort(oldpos);
            newpos(tags)=newpos;
        end
    end
end
function y=re_inflator(x,state)
y=zeros(length(state),1);
y(state)=x;
end