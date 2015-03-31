require 'pivotal-tracker'

require 'pp'
 
config_file = File.dirname(File.expand_path(__FILE__)) + '/../config/pivotal.yml'
config = YAML::load(File.open(config_file))

 
PivotalTracker::Client.token = config['pivotal_api_token']

def newrelease(starts)
  rel = { stories:0, stories_p:0, accepted_p:0, accepted_s:0, name:'', deadline:0, start:starts }
end
  

def getproject(projid)
  @project = PivotalTracker::Project.find projid
 
  if @project.is_a?(PivotalTracker::Project)
    puts "Current velocity #{@project.current_velocity}"
    @current = PivotalTracker::Iteration.current(@project)
    @iteration_seconds = @current.finish.strftime('%s').to_i - @current.start.strftime('%s').to_i
    @backlog = @current.stories
    PivotalTracker::Iteration.backlog(@project).each do |iteration|
      @backlog.concat iteration.stories
    end
    proj = []
    @releaseno=0
    proj[@releaseno]=newrelease(@current.start.strftime('%s').to_i)

    @backlog.each do |story|
      
      if story.story_type == 'release'
        proj[@releaseno][:name] = story.name
        if story.deadline
          proj[@releaseno][:deadline] = story.deadline.strftime('%s').to_i
          puts "has deadline #{proj[@releaseno][:deadline]}"
        else
          proj[@releaseno][:deadline] =
             (proj[@releaseno][:stories_p]-proj[@releaseno][:accepted_p]) * @iteration_seconds / @project.current_velocity.to_i
          puts "calculate deadline #{proj[@releaseno][:deadline]}"
          if @releaseno > 0
            proj[@releaseno][:deadline] += proj[@releaseno-1][:deadline]
            puts "update deadline #{proj[@releaseno][:deadline]}"
          else
            proj[@releaseno][:deadline] += Time.now.to_i
            puts "update deadline #{proj[@releaseno][:deadline]}"
          end
        end
        @releaseno+=1
        if @releaseno >= 4
          break
        end
        proj[@releaseno]=newrelease(proj[@releaseno-1][:deadline])
      else
        proj[@releaseno][:stories]+=1
        proj[@releaseno][:stories_p]+=story.estimate
        if story.current_state == 'accepted'
          proj[@releaseno][:accepted_s]+=1
          proj[@releaseno][:accepted_p]+=story.estimate
        end
      end
    end 
    proj
 
  else
    puts 'Not a Pivotal project'
    nil
  end
end

def sendproject(rels)
  pp rels
  for @rno in 0..3
    @days_left = (Time.at(rels[@rno][:deadline]).to_date - Date.today).to_i
    if @days_left > 0
      @due = "Due in #{@days_left} days"
    elsif @days_left == 0
      @due = "Due today"
    else
      @due = "OVERDUE by #{@days_left.abs} days"
    end
    @moreinfo = "Accepted #{rels[@rno][:accepted_p]} of #{rels[@rno][:stories_p]} points, #{rels[@rno][:accepted_s]} (#{rels[@rno][:stories]}) stories"
    send_event("release-#{@rno+1}", { milestone:rels[@rno][:name], time:@due, moreinfo:@moreinfo})
    puts "sending event for release-#{@rno+1} #{rels[@rno][:name]}"
  end
end

SCHEDULER.every '30m', :first_in => 0 do
  config['pivotal_project'].each do |proj|
    @p = getproject( proj['item']['id'])
    sendproject(@p)
  end
end
