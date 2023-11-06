function plotrasters_(data,meta,fun,opt)
%UNTITLED3 Summary of this function goes here
%   Detailed explanation goes here

% argument validation
arguments
    data table
    meta struct
    fun function_handle
    opt.alignment string
    opt.sorting (:,:) cell
    opt.xlim (1,2) double
    opt.xlabel string
    opt.ylabel string
    opt.savepath string
end

% iterate through mice
for mm = 1 : meta.mice.n
    mouse_flags = data.mouse == meta.mice.ids{mm};
    trial_flags = ...
        mouse_flags;
    n_trials = sum(trial_flags);
    
    % parse session data
    n_sessions = max(data.session(mouse_flags));
    n_rewards_per_session = arrayfun(@(x) ...
        sum(data.session(trial_flags) == x),1:n_sessions);
    session_delims = [1,cumsum(n_rewards_per_session)];
    session_clrs = cool(n_sessions);
    
    % figure initialization
    figure(...
        'numbertitle','off',...
        'name',sprintf('%s_%s_da_rasters_%s_%s',...
        meta.experiment,meta.mice.ids{mm},opt.alignment,opt.sorting{end}),...
        'color','w');
    
    % axes initialization
    yytick = session_delims;
    yyticklabel = num2cell(yytick);
    yyticklabel(2:end-1) = {''};
    axes(defaultaxesoptions,...
        'xlim',opt.xlim,...
        'ylim',[0,n_trials],...
        'ytick',yytick,...
        'yticklabel',yyticklabel,...
        'colormap',bone(2^8-1));
    
    % axes labels
    title(sprintf('%s',meta.mice.ids{mm}));
    xlabel(opt.xlabel);
    ylabel(opt.ylabel);
    
    % trial sorting
    [~,sorted_idcs] = sortrows(data(trial_flags,:),opt.sorting);
    
    % plot raster
    flagged_data = data(trial_flags,:);
    fun(flagged_data(sorted_idcs,:),meta,opt);
%     da_mat = data.da.(opt.alignment)(trial_flags,:);
%     imagesc(meta.epochs.(opt.alignment),[0,n_trials]+[1,-1]*.5,...
%         da_mat(sorted_idcs,:),quantile(da_mat,[.001,.999],'all')');
    
    % plot reaction times
    if strcmpi(opt.alignment,'delivery')
        reaction_times = data.rt(trial_flags);
    else
        reaction_times = -data.rt(trial_flags);
    end
    session_idcs = data.session(trial_flags);
    scatter(...
        reaction_times(sorted_idcs),1:n_trials,7.5,...
        session_clrs(session_idcs(sorted_idcs),:),...
        'marker','.');
    
    % iterate through sessions
    for ss = 1 : n_sessions

        % plot session delimeters
        if ss < n_sessions
            plot(xlim,[1,1]*session_delims(ss+1),...
                'color','w',...
                'linestyle',':');
        end
        
        % patch session edge bands
        xpatch = ...
            [1,1,1,1] * min(xlim) + ...
            [0,1,1,0] * range(xlim) * .025;
        ypatch = ...
            [1,1,0,0] * session_delims(ss) + ...
            [0,0,1,1] * session_delims(ss+1);
        patch(xpatch,ypatch,session_clrs(ss,:),...
            'edgecolor','none',...
            'facealpha',1);
    end
    
    % plot alignment line
    plot([0,0],ylim,'--w');
    
    % save figure
    if ~isempty(opt.savepath)
        file_name = sprintf('%s',[get(gcf,'name'),'.png']);
        file_path = fullfile(opt.savepath,file_name);
        print(gcf,file_path,'-dpng','-r300','-painters');
    end
end
end