class Users::SessionsController < Devise::SessionsController
  # POST /users/sign_in
  def create
    super
  end

  # DELETE /users/sign_out
  def destroy
    super
  end
end