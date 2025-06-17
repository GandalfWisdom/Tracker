--!strict
local require = require(script.Parent.loader).load(script) :: any;
local KeyframeSequenceProvider: KeyframeSequenceProvider = game:GetService("KeyframeSequenceProvider");
local Maid = require("Maid");
local Signal = require("Signal");

local Tracker = {};
Tracker.__index = Tracker;
Tracker.ClassName = "Tracker";

export type Tracker = typeof(setmetatable(
    {} :: {
        _maid: Maid.Maid,
		_track_maid: Maid.Maid,
		_anim_folder: Folder,
		plr: Player,
		char: Model,
		humanoid: Humanoid,
		animator: Animator,
		TrackEvent: Signal.Signal<string>,
		anims: { [string]: Animation },
		tracks: { [string]: AnimationTrack },
		track_events: { [string]: { [number]: string } },
		last_track: AnimationTrack?
    },
   {} :: typeof({ __index = Tracker })
));

--[=[
    Constructs a new Tracker object
    @return Tracker
]=]
function Tracker.new(anims_folder: Folder): Tracker
	assert(anims_folder, "Animation folder invalid!");
	local self: Tracker = setmetatable({} :: any, Tracker);
	self._maid = Maid.new();
	self._track_maid = self._maid:Add(Maid.new());
	self._anim_folder = anims_folder;
	self.plr = game:GetService("Players").LocalPlayer;
	self.char = self.plr.Character or self.plr.CharacterAdded:Wait();
	self.humanoid = self.char:WaitForChild("Humanoid") :: Humanoid;
	self.animator = self.humanoid:FindFirstChildOfClass("Animator") :: Animator;

	self.TrackEvent = self._maid:Add(Signal.new());
	self.anims = {};
	self.tracks = {};
	self.track_events = {};
	self.last_track = nil;

	self:Init();
	return self;
end;

--[=[
    Plays a specified animation.
	@param action string -- Name of the animation to play.
	@param playback_speed number -- How fast the animation plays.
	@param weight number -- Weight of the animation to be played.
	@param exclusive boolean -- Will stop all other currently playing animations before playing.
]=]
function Tracker.Play(self: Tracker, action: string, playback_speed: number?, weight: number?, exclusive: boolean?): ()
	local track = self.tracks[action];
	if not (track) then return; end;

	--STOPS ALL OTHER ANIMS IF EXCLUSIVE
	if (exclusive) then
		self:StopAll();
	end;
	
	--SETS DEFAULT VALUES
	if not (playback_speed) then
		playback_speed = 1;
	end;
	if not (weight) then
		weight = 1;
	end;
	
	if not (track.IsPlaying) then
		track:AdjustWeight(weight, 0.1);
		track:Play();
		track:AdjustSpeed(playback_speed);
		self.last_track = track;
	end;
end;

--[=[
    Plays a specified animation after the previous animation finishes.
	@param action string -- Name of the animation to play.
	@param playback_speed number -- How fast the animation plays.
	@param weight number -- Weight of the animation to be played.
	@param exclusive boolean -- Will stop all other currently playing animations before playing.
]=]
function Tracker.AndThenPlay(self: Tracker, action: string, playback_speed: number, weight: number, exclusive: boolean): ()
	if not (self.last_track) then return; end;

	self._track_maid:GiveTask(self.last_track.Ended:Connect(function()
		self:Play(action, playback_speed, weight, exclusive);
		self._track_maid:DoCleaning();
	end));
end;

--[=[
    Stops specified animation
	@param action string -- Name of the animation to stop.
]=]
function Tracker.Stop(self: Tracker, action: string)
	local track = self.tracks[action];
	if not (track) then return; end;

	--STOP SPECIFIC ANIMATION
	if (track.IsPlaying) then
		track:Stop();
	end;
end;

--[=[
    Stops all animations currently playing.
]=]
function Tracker.StopAll(self: Tracker): ()
	for index, anim_track in pairs(self.tracks) do
		if (anim_track.IsPlaying) then
			anim_track:Stop();
		end;
	end;
end;

--[=[
   	Gets all events in animation track.
]=]
function Tracker.GetTrackEvents(self: Tracker): { [string]: { [number]: string } }
	local track_events: { [string]: { [number]: string } } = {};
	for index, anim in pairs(self.anims) do
		local keyframe_sequence: KeyframeSequence;
		local success, _ = pcall(function()
			keyframe_sequence = KeyframeSequenceProvider:GetKeyframeSequenceAsync(anim.AnimationId) :: KeyframeSequence;
		end);
		if not (success) then continue; end;
		local markers: { [number]: string } = {};
		for _, keyframe in pairs(keyframe_sequence:GetKeyframes()) do -- Loop through keyframe sequence
			if not (keyframe:IsA("Keyframe")) then continue; end;
			for _, marker in pairs(keyframe:GetMarkers()) do
				if not (marker:IsA("KeyframeMarker")) then continue; end;
				table.insert(markers, marker.Name);
			end;
		end;
		if (#markers > 0) then track_events[index] = markers; end;
	end;
	return track_events;
end;

--[=[
    Set tracker events. Sets all AnimationReachedSignal events to fire event.
]=]
function Tracker.SetEvents(self: Tracker): ()
	for track_name, _ in pairs(self.tracks) do -- Sets GetMarkerReachedSignal events
		if not (self.track_events[track_name]) then continue; end;
		for _, event in pairs(self.track_events[track_name]) do
			self._maid:GiveTask(self.tracks[track_name]:GetMarkerReachedSignal(event):Connect(function()
				self.TrackEvent:Fire(event);
			end));
		end;
	end;
end;

--[=[
    Intializes Tracker class.
]=]
function Tracker.Init(self: Tracker): ()
	-- LOAD ANIMS INTO USABLE TABLE.
	for _, anim_instance in pairs(self._anim_folder:GetDescendants()) do
		if (anim_instance:IsA("Animation")) then
			self.anims[anim_instance.Name] = anim_instance;
		end;
	end;
	-- LOAD ANIM INTO USABLE TRACKS IN TABLE.
	for index, anim in pairs(self.anims) do
		self.tracks[index] = self._maid:Add(self.animator:LoadAnimation(anim));
	end;
	-- LOAD ANIM EVENTS INTO TABLE.
	self.track_events = self:GetTrackEvents();
	--Set events.
	self:SetEvents();
end;

--[=[
    Cleans up the class object and sets the metatable to nil
]=]
function Tracker.Destroy(self: Tracker): ()
	self:StopAll();
    self._maid:DoCleaning();
    setmetatable(self :: any, nil);
end;

return Tracker;