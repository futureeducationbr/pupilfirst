class BatchApplicationController < ApplicationController
  before_action :ensure_applicant_is_signed_in, except: %w(index register identify send_sign_in_email continue sign_in_email_sent)
  before_action :ensure_batch_active, except: :index
  before_action :ensure_accurate_stage_number, only: %w(ongoing submit complete restart expired rejected)
  before_action :set_instance_variables
  before_action :hide_nav_links

  layout 'application_v2'

  helper_method :current_batch_applicant
  helper_method :current_batch
  helper_method :current_stage
  helper_method :current_application
  helper_method :applicant_stage
  helper_method :applicant_stage_number
  helper_method :applicant_status

  # GET /apply
  def index
    # Redirect current batch's applicants to continue route.
    return redirect_to(apply_continue_path) if current_batch&.applied?(current_batch_applicant)

    @form = BatchApplicationForm.new(BatchApplication.new)
    @form.prepopulate!(team_lead: BatchApplicant.new)
  end

  # POST /apply/register
  def register
    batch_application = BatchApplication.new
    batch_application.team_lead = BatchApplicant.new
    @form = BatchApplicationForm.new(batch_application)

    if @form.validate(params[:batch_application])
      applicant = @form.save

      sign_in_applicant_temporarily(applicant)

      redirect_to apply_stage_path(stage_number: applicant_stage_number, continue_mail_sent: 'yes')
    else
      render 'index'
    end
  end

  # GET /apply/identify
  def identify
    @form = BatchApplicantSignInForm.new(BatchApplicant.new)
  end

  # POST /apply/send_sign_in_email
  def send_sign_in_email
    @skip_container = true

    @form = BatchApplicantSignInForm.new(BatchApplicant.new)

    if @form.validate(params[:batch_applicant_sign_in])
      @form.save

      # Kick out session based login if a manual login is requested. This allows applicant to change signed-in ID.
      session.delete :applicant_token

      redirect_to apply_sign_in_email_sent_path(batch_number: params[:batch_number])
    else
      render 'batch_application/identify'
    end
  end

  # GET /apply/sign_in_email_sent
  def sign_in_email_sent
    @skip_container = true
  end

  # GET /apply/continue
  #
  # This is the link supplied in emails. Routes applicant to correct location.
  def continue
    check_token

    # TODO: Consider case where there is no ongoing batch.

    case applicant_status
      when :application_pending
        redirect_to apply_path
      when :ongoing
        redirect_to apply_stage_path(stage_number: applicant_stage_number)
      when :expired
        redirect_to apply_stage_expired_path(stage_number: applicant_stage_number)
      when :rejected
        redirect_to apply_stage_rejected_path(stage_number: applicant_stage_number)
      when :complete
        redirect_to apply_stage_complete_path(stage_number: current_stage_number)
      else
        raise "Unexpected applicant_status: #{applicant_status}"
    end
  end

  # POST /apply/restart
  def restart_application
    # Only applications in stage 1 can restart.
    raise_not_found if applicant_stage_number != 1
    current_application&.restart!

    flash[:success] = 'Your previous application has been discarded.'

    redirect_to apply_path
  end

  # GET /apply/stage/:stage_number
  def ongoing
    return redirect_to(apply_continue_path) if applicant_status != :ongoing
    try "stage_#{applicant_stage_number}"
    render "stage_#{applicant_stage_number}"
  end

  # POST /apply/stage/:stage_number/submit
  def submit
    raise_not_found if applicant_status != :ongoing

    begin
      send "stage_#{applicant_stage_number}_submit"
    rescue NoMethodError
      raise_not_found
    end
  end

  # GET /apply/stage/:stage_number/complete
  def complete
    return redirect_to(apply_continue_path) if applicant_status != :complete
    try "stage_#{applicant_stage_number}_complete"
    render "stage_#{current_stage_number}_complete"
  end

  # POST /apply/stage/:stage_number/restart
  def restart
    return redirect_to(apply_continue_path) if applicant_status != :complete
    raise_not_found if current_batch.stage_expired?

    begin
      send "stage_#{applicant_stage_number}_restart"
    rescue NoMethodError
      raise_not_found
    end
  end

  # GET /apply/stage/:stage_number/expired
  def expired
    return redirect_to(apply_continue_path) if applicant_status != :expired
    try "stage_#{applicant_stage_number}_expired"
    render "stage_#{applicant_stage_number}_expired"
  end

  # GET /apply/stage/:stage_number/rejected
  def rejected
    return redirect_to(apply_continue_path) if applicant_status != :rejected
    try "stage_#{applicant_stage_number}_rejected"
    render "stage_#{applicant_stage_number}_rejection"
  end

  ####
  ## Public methods after this after called with 'try'.
  ####

  def stage_1
    @continue_mail_sent = params[:continue_mail_sent]
    @form = ApplicationStageOneForm.new(current_application)
  end

  def stage_1_submit
    # Save number of cofounders, and redirect to Instamojo.
    @form = ApplicationStageOneForm.new(current_application)

    if @form.validate(params[:application_stage_one])
      begin
        payment = @form.save
      rescue Instamojo::PaymentRequestCreationFailed
        flash[:error] = 'We were unable to contact our payment partner. Please try again in a few minutes.'
        redirect_to apply_stage_path(stage_number: 1, error: 'payment_request_failed')
        return
      end

      if Rails.env.development?
        render text: "Redirect to #{payment.long_url}"
      else
        redirect_to payment.long_url
      end
    else
      render 'stage_1'
    end
  end

  def stage_2
    application_submission = ApplicationSubmission.new
    @form = ApplicationStageTwoForm.new(application_submission)
  end

  def stage_2_submit
    application_submission = ApplicationSubmission.new(
      application_stage: current_stage,
      batch_application: current_application
    )

    @form = ApplicationStageTwoForm.new(application_submission)

    if @form.validate(params[:application_stage_two])
      @form.save
      redirect_to apply_stage_complete_path(stage_number: '2')
    else
      render 'batch_application/stage_2'
    end
  end

  def stage_2_restart
    stage_2_submission = current_application.application_submissions.where(application_stage_id: applicant_stage.id).first
    stage_2_submission.destroy!
    redirect_to apply_stage_path(stage_number: 2)
  end

  def stage_4_submit
    # TODO: Server-side error handling for stage 4 inputs.

    # TODO: How to handle file uploads (if any for pre-selection)?
    current_application.application_submissions.create!(
      application_stage: current_stage
    )

    redirect_to apply_stage_complete_path(stage_number: '4')
  end

  protected

  # Returns currently active batch.
  def current_batch
    @current_batch ||= begin
      Batch.open_batch
    end
  end

  # Returns the application_stage that current batch is at.
  def current_stage
    @current_stage ||= current_batch&.application_stage
  end

  # Returns the stage number of current batch.
  def current_stage_number
    @current_stage_number ||= current_stage&.number.to_i
  end

  def applicant_stage
    @applicant_stage ||= begin
      if current_application.blank?
        ApplicationStage.find_by number: 1
      else
        current_application.application_stage
      end
    end
  end

  # Returns stage number of current applicant.
  def applicant_stage_number
    @applicant_stage_number ||= applicant_stage.number
  end

  # Returns batch application of current applicant.
  def current_application
    @current_application ||= current_batch_applicant&.batch_applications&.find_by(batch: current_batch)
  end

  # Returns currently 'signed in' application founder.
  def current_batch_applicant
    @current_batch_applicant ||= begin
      token = session[:applicant_token] || cookies[:applicant_token]
      BatchApplicant.find_by token: token
    end
  end

  # Returns one of :application_pending, :ongoing, :expired, :rejected, :complete to indicate which view should be rendered.
  #
  # rubocop:disable Metrics/PerceivedComplexity, Metrics/CyclomaticComplexity, Metrics/MethodLength
  def applicant_status
    @applicant_status ||= begin
      if current_application.blank?
        :application_pending
      elsif applicant_stage_number == 1
        if current_stage_number == 1 || (current_stage_number == 2 && !stage_expired?)
          :ongoing
        else
          :expired
        end
      elsif applicant_stage_number == current_stage_number
        if applicant_has_submitted?
          :complete
        else
          stage_expired? ? :expired : :ongoing
        end
      elsif applicant_stage_number > current_stage_number
        :complete
      else
        applicant_has_submitted? ? :rejected : :expired
      end
    end
  end

  private

  def set_instance_variables
    @skip_container = true
    @hide_sign_in = true
  end

  def login_state
    cached_status = applicant_status

    case cached_status
      when :application_pending, :application_expired, :payment_pending
        cached_status.to_s
      else
        "stage_#{applicant_stage_number}_#{cached_status}"
    end
  end

  def applicant_has_submitted?
    return true if applicant_stage_number == 1

    ApplicationSubmission.where(
      batch_application_id: current_application.id,
      application_stage_id: applicant_stage.id
    ).present?
  end

  # Batch's stage should have expired, and current stage should be same as application stage.
  def stage_expired?
    current_batch.stage_expired?
  end

  # Check whether a token parameter has been supplied. Sign in application founder if there's a corresponding entry.
  def check_token
    return if params[:token].blank?
    applicant = BatchApplicant.find_by token: params[:token]

    if applicant.blank?
      flash[:error] = 'That token is invalid.'
      return
    end

    # Sign in the current application founder.
    @current_batch_applicant = applicant

    if params[:shared_device] == 'true'
      # If applicant has indicated that zhe is on a shared device, create session variable instead of cookie.
      session[:applicant_token] = applicant.token
    else
      # Store a cookie that'll keep applicant signed in for 3 months.
      cookies[:applicant_token] = { value: applicant.token, expires: 3.months.from_now }
    end
  end

  # Redirect applicant to sign in page is zhe isn't signed in.
  def ensure_applicant_is_signed_in
    return if current_batch_applicant.present?
    redirect_to apply_identify_url(batch: params[:batch_number])
  end

  def ensure_batch_active
    raise_not_found if current_stage_number == 0
  end

  def ensure_accurate_stage_number
    expected_stage_number = if current_stage_number == 1 && applicant_stage_number == 2
      1
    else
      applicant_stage_number
    end

    redirect_to apply_continue_path if params[:stage_number].to_i != expected_stage_number
  end

  def sign_in_applicant_temporarily(applicant)
    session[:applicant_token] = applicant.token
  end

  def hide_nav_links
    @hide_nav_links = true
  end
end
