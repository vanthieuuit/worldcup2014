class MatchController < ApplicationController
  before_filter :authenticate_user!, only: [:betting, :update_score]
  def index
  end
  def show
    @game = Game.find(params[:game_id])
    @scores = Score.all.collect{|s|[s.name, s.id]}
    @selected_scores = current_user.user_scores.where(game_id: @game.id).collect{|a|a.score_id} if user_signed_in?
    # @disabled = (@game.deadline.to_date == Date.today && Time.now.hour < @game.deadline.hour) ? false : true
    @disabled = false

    # Statistics
    @statistics = @game.user_scores.group_by(&:user_id)

    # Money Betting
    games_ordered = Game.order(:play_at, :pos)
    index_current_game = games_ordered.index(@game)
    @money_from_previous_match = @game.pos > 1 ? Investment.where(game_id: games_ordered[index_current_game-1].id).first.remaining : 0
    total_budgets_bet = Budget.where(game_id: @game.id).map(&:total_money_bet).sum
    @money_users_bet = total_budgets_bet
    @money_company_contribute = total_budgets_bet.zero? ? 0 : 3*@game.round.amount
    @total_money = @money_users_bet + @money_company_contribute + @money_from_previous_match
    # Update money for final match
    if @game.id == 64
      @total_money_for_final = Investment.all.map(&:remaining).sum
      @total_money = @total_money + @total_money_for_final
    end

    # Winners of this match
    @no_winner = false
    user_budget_winners = Budget.where(game_id: @game.id).where("total_money_win > 0")
    winner_ids = user_budget_winners.map(&:user_id)
    unless winner_ids.blank?
      @winners = User.where(id: winner_ids).collect {|w| w.display_name}.join(', ')
      @amount_of_money = user_budget_winners.first.total_money_win
    else
      @no_winner = true
    end
  end

  def betting
    game = Game.find(params[:game_id])
    unit_price = game.round.amount

    unless params[:user_scores].blank?
      if params[:user_scores].size > 3
        flash[:error] = "Cannot bet greater than 3 scores!"
      elsif params[:user_scores].size > 0
        # if game.deadline.to_date == Date.today && Time.now.hour < game.deadline.hour
        if true
          existing_scores = current_user.user_scores.where(game_id: game.id)
          unless existing_scores.blank?
            existing_scores.delete_all
          end
          params[:user_scores].each do |score|
            UserScore.create(user_id: current_user.id, score_id: score, game_id: params[:game_id], bid_date: Date.today)
          end
          # Update budget
          user_budget = Budget.where(user_id: current_user.id, game_id: game.id).first
          if user_budget.blank?
            Budget.create(game_id: game.id, user_id: current_user.id, total_money_bet: params[:user_scores].size * unit_price)
          else
            user_budget.update_attributes(total_money_bet: params[:user_scores].size * unit_price)
          end
          flash[:notice] = "Successfully!"
        elsif game.deadline.to_date == Date.today && Time.now.hour >= game.deadline.hour
          flash[:error] = "Cannot bet this match! You can only bet before #{game.deadline.strftime('%-l%P, %d-%m-%Y')}!"
        else
          flash[:error] = "Cannot bet this match! You can only bet in #{game.deadline.strftime('%d-%m-%Y')}!"
        end
      end
    else
      existing_scores = current_user.user_scores.where(game_id: game.id)
      # if !existing_scores.blank? && game.deadline.to_date == Date.today && Time.now.hour < game.deadline.hour
      if !existing_scores.blank? && true
        existing_scores.delete_all
        # Update budget
        user_budget = Budget.where(user_id: current_user.id, game_id: game.id).first
        user_budget.update_attributes(total_money_bet: 0)
        flash[:notice] = "Successfully!"
      end
    end
    redirect_to :back
  end

  def update_score
    @game = Game.find(params[:game_id])
    @scores = Score.all.collect{|s|[s.name, s.id]}
    if current_user.admin? && request.post?
      score = Score.find(params[:score_id])
      score_result = score.name.split('-')
      if @game.update_attributes(score1: score_result[0].to_i, score2: score_result[1].to_i, score_id: score.id, locked: true, winner: params[:result].to_i > 0 ? params[:result].to_i : nil)
        # List winner of this match
        list_winners_arr = @game.user_scores.where(score_id: @game.score_id).group_by(&:user_id).keys
        investment = Investment.find_by_game_id(@game.id)
        total_money_for_final = @game.id == 64 ? Investment.all.map(&:remaining).sum : 0
        # Find previous game
        games_ordered = Game.order(:play_at, :pos)
        index_current_game = games_ordered.index(@game)
        money_from_previous_match = @game.pos > 1 ? Investment.where(game_id: games_ordered[index_current_game-1].id).first.remaining : 0
        if list_winners_arr.size > 0
          # Reset total money win
          Budget.where(game_id: @game.id).update_all(total_money_win: 0)
          # Update total money win
          money_for_each_people = ((investment.total + money_from_previous_match + total_money_for_final).to_f / list_winners_arr.size).round
          Budget.where(user_id: list_winners_arr, game_id: @game.id).update_all(total_money_win: money_for_each_people)
          investment.update_attributes(remaining: 0) if !investment.remaining.blank?
        else
          Budget.where(game_id: @game.id).update_all(total_money_win: 0)
          investment.update_attributes(remaining: ((investment.total + money_from_previous_match + total_money_for_final).to_f / 2).round)
        end
        flash[:notice] = "Update score successfully!"
      else
        flash[:error] = "Cannot update score!"
      end
      redirect_to match_game_path(@game)
    end
  end

  def betting_score
    @game = Game.find(params[:game_id])
    unit_price = @game.round.amount
    @users = User.where(admin: false).order(:username)
    @scores = Score.all.collect{|s|[s.name, s.id]}
    @disabled = false
    if current_user.admin? && request.post?
      unless params[:user].blank?
        params[:user].each do |user_id, score|
          score[:score_ids].each do |score_id|
            UserScore.create(user_id: user_id, score_id: score_id, game_id: params[:game_id], bid_date: Date.today)
          end
          # Update budget
          user_budget = Budget.where(user_id: user_id, game_id: @game.id).first
          if user_budget.blank?
            Budget.create(game_id: @game.id, user_id: user_id, total_money_bet: score[:score_ids].size * unit_price)
          else
            user_budget.update_attributes(total_money_bet: score[:score_ids].size * unit_price)
          end
        end
      end
    end
  end
end